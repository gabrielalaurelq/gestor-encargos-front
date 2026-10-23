import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/domain/dia.dart';
import '../../../shared/domain/monto.dart';
import '../../../shared/domain/telefono.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/infrastructure/db/base_datos.dart';
import '../../../shared/sync/numeracion.dart';
import '../../../shared/sync/outbox.dart';
import '../../../shared/sync/recalculo.dart';
import '../../clientes/domain/cliente.dart';
import '../domain/encargo.dart';
import '../domain/encargo_nuevo.dart';
import '../domain/estado_encargo.dart';

/// Los encargos en la base local. Mismo patrón que clientes y catálogo: cada
/// escritura va a Drift y encola su envío en la misma transacción, sin
/// adelantar `actualizado_en` (ver `sinVersionDelServidor`).
abstract final class TiposEncargo {
  static const crear = TiposOperacion.crearEncargo;
  static const editar = 'editar_encargo';
  static const cambiarEstado = 'cambiar_estado';
}

class RepositorioEncargos {
  RepositorioEncargos({
    required this._base,
    required this._outbox,
    required this._numeracion,
    String Function()? nuevoId,
    DateTime Function()? reloj,
  }) : _nuevoId = nuevoId ?? const Uuid().v4,
       _reloj = reloj ?? DateTime.now;

  final BaseDatos _base;
  final Outbox _outbox;
  final Numeracion _numeracion;
  final String Function() _nuevoId;
  final DateTime Function() _reloj;

  /// Un encargo con su cliente, reactivo: cambia solo cuando se edita o baja
  /// una versión nueva. `null` si no existe.
  Stream<Encargo?> observar(String id) {
    final consulta = _base.select(_base.encargos).join([
      leftOuterJoin(_base.clientes, _base.clientes.id.equalsExp(_base.encargos.clienteId)),
    ])..where(_base.encargos.id.equals(id));
    return consulta.watchSingleOrNull().map(
      (fila) => fila == null
          ? null
          : _aEncargo(fila.readTable(_base.encargos), fila.readTableOrNull(_base.clientes)),
    );
  }

  /// Alta mínima (Caso 7). El número sale del bloque reservado, sin red, en la
  /// misma transacción: un número tomado y no usado sería un hueco. Una fecha
  /// pasada se acepta (decisión del usuario: pasar encargos del cuaderno).
  ///
  /// Nace como en el backend: INGRESADO, total y saldo en cero, y la fecha
  /// prometida igual a la acordada (Doc 2, invariante 6; no se envía).
  Future<EncargoNuevo> crear({
    required String clienteId,
    required String descripcion,
    required DateTime fechaEntregaAcordada,
  }) async {
    final limpia = ReglasEncargo.validarDescripcion(descripcion);
    final id = _nuevoId();
    final fecha = isoDesdeDia(fechaEntregaAcordada);
    return _base.transaction(() async {
      final numero = await _numeracion.tomar();
      await _base
          .into(_base.encargos)
          .insert(
            EncargosCompanion.insert(
              id: id,
              creadoEn: _reloj().toUtc().toIso8601String(),
              actualizadoEn: sinVersionDelServidor,
              clienteId: clienteId,
              numero: Value(numero),
              descripcion: limpia,
              estado: EstadoEncargo.ingresado.codigo,
              precioTotal: 0,
              descuento: 0,
              saldoPendiente: 0,
              fechaEntregaPrometida: fecha,
              fechaEntregaAcordada: fecha,
            ),
          );
      await _outbox.encolar(
        OperacionNueva(
          tipo: TiposEncargo.crear,
          metodo: 'POST',
          ruta: '/encargos',
          cuerpo: {
            'id': id,
            'cliente_id': clienteId,
            // Sin número viaja sin la clave: se le asigna justo antes de subir.
            'numero': ?numero,
            'descripcion': limpia,
            'fecha_entrega_acordada': fecha,
          },
          entidadId: id,
          encargoId: id,
        ),
      );
      return EncargoNuevo(id: id, numero: numero);
    });
  }

  /// Datos generales (S2c): `PATCH` solo con lo que cambió; sin cambios no
  /// encola nada y devuelve `false`. Ubicación y notas vacías se borran
  /// (`null` explícito, como hace el backend). Reprogramar mueve solo la
  /// acordada: la prometida queda como testigo (Doc 2, invariantes 6-7).
  ///
  /// Un encargo entregado o cancelado no se reprograma ni cambia su
  /// descuento (decisiones del usuario); el backend lo permitiría, la app no.
  ///
  /// [descuento] `null` = no se toca. Se valida contra la suma de trabajos
  /// **de Drift, dentro de la transacción** (no contra lo que mostraba la
  /// pantalla) y se recalculan total y saldo (S3b2).
  Future<bool> editar(
    Encargo actual, {
    required String descripcion,
    required DateTime fechaEntregaAcordada,
    required String ubicacion,
    required String notas,
    Monto? descuento,
  }) async {
    final limpia = ReglasEncargo.validarDescripcion(descripcion);
    final reprograma = fechaEntregaAcordada != actual.fechaEntregaAcordada;
    final nuevoDescuento = descuento == null || descuento == actual.descuento
        ? null
        : ReglasEncargo.validarDescuento(descuento, null);
    final cerrado = actual.estado?.cerrado ?? false;
    if (reprograma && cerrado) {
      throw const ValorInvalido(
        'ENCARGO_CERRADO',
        'Un encargo entregado o cancelado no se reprograma.',
      );
    }
    if (nuevoDescuento != null && cerrado) {
      throw const ValorInvalido(
        'ENCARGO_CERRADO',
        'Un encargo entregado o cancelado no cambia su descuento.',
      );
    }
    String? opcional(String texto) => texto.trim().isEmpty ? null : texto.trim();
    final nuevaUbicacion = opcional(ubicacion);
    final nuevasNotas = opcional(notas);
    final cuerpo = <String, Object?>{
      if (limpia != actual.descripcion) 'descripcion': limpia,
      if (reprograma) 'fecha_entrega_acordada': isoDesdeDia(fechaEntregaAcordada),
      if (nuevaUbicacion != actual.ubicacionFisica) 'ubicacion_fisica': nuevaUbicacion,
      if (nuevasNotas != actual.notasGenerales) 'notas_generales': nuevasNotas,
      if (nuevoDescuento != null) 'descuento': nuevoDescuento.soles,
    };
    if (cuerpo.isEmpty) return false;
    return _base.transaction(() async {
      if (nuevoDescuento != null) {
        ReglasEncargo.validarDescuento(nuevoDescuento, await _sumaTrabajos(actual.id));
      }
      final filas = await (_base.update(_base.encargos)..where((e) => e.id.equals(actual.id)))
          .write(
            EncargosCompanion(
              descripcion: Value(limpia),
              fechaEntregaAcordada: Value(isoDesdeDia(fechaEntregaAcordada)),
              ubicacionFisica: Value(nuevaUbicacion),
              notasGenerales: Value(nuevasNotas),
              descuento: nuevoDescuento == null
                  ? const Value.absent()
                  : Value(nuevoDescuento.centimos),
            ),
          );
      if (filas == 0) throw StateError('No existe el encargo ${actual.id}');
      if (nuevoDescuento != null) await recalcularTotales(_base, actual.id);
      await _outbox.encolar(
        OperacionNueva(
          tipo: TiposEncargo.editar,
          metodo: 'PATCH',
          ruta: '/encargos/${actual.id}',
          cuerpo: cuerpo,
          entidadId: actual.id,
          encargoId: actual.id,
        ),
      );
      return true;
    });
  }

  /// `PATCH /encargos/{id}/estado` con la fecha del teléfono (Doc 5 v1.4),
  /// y sus efectos en Drift como los aplica el backend (`transicionarA`):
  /// LISTO marca `fecha_listo` si no la tenía; ENTREGADO marca
  /// `fecha_entrega_real` y, si se saltó LISTO, también `fecha_listo` con el
  /// mismo día. Pausar o cancelar no borra ninguna fecha.
  ///
  /// El estado de partida se lee de Drift dentro de la transacción, no de lo
  /// que mostraba la pantalla. Al mismo estado devuelve `false` sin encolar
  /// nada; una transición que el backend rechazaría da
  /// `TRANSICION_INVALIDA`. El aviso de saldo pendiente al entregar es de la
  /// pantalla, antes de llamar (PRD módulo 6: avisa, no bloquea).
  Future<bool> cambiarEstado(String encargoId, EstadoEncargo destino) =>
      _base.transaction(() async {
        final fila = await (_base.select(
          _base.encargos,
        )..where((e) => e.id.equals(encargoId))).getSingleOrNull();
        if (fila == null) throw StateError('No existe el encargo $encargoId');
        final actual = EstadoEncargo.desde(fila.estado);
        if (actual == destino) return false;
        if (actual == null || !actual.puedePasarA(destino)) {
          throw ValorInvalido(
            'TRANSICION_INVALIDA',
            actual == EstadoEncargo.entregado
                ? 'Un encargo entregado ya no cambia de estado.'
                : 'Un encargo ${actual?.etiqueta.toLowerCase() ?? fila.estado} no puede '
                      'pasar a ${destino.etiqueta.toLowerCase()}.',
          );
        }
        final hoy = isoDesdeDia(hoyDelNegocio(_reloj()));
        final listo = destino == EstadoEncargo.listo || destino == EstadoEncargo.entregado;
        await (_base.update(_base.encargos)..where((e) => e.id.equals(encargoId))).write(
          EncargosCompanion(
            estado: Value(destino.codigo),
            fechaListo: listo && fila.fechaListo == null ? Value(hoy) : const Value.absent(),
            fechaEntregaReal: destino == EstadoEncargo.entregado && fila.fechaEntregaReal == null
                ? Value(hoy)
                : const Value.absent(),
          ),
        );
        await _outbox.encolar(
          OperacionNueva(
            tipo: TiposEncargo.cambiarEstado,
            metodo: 'PATCH',
            ruta: '/encargos/$encargoId/estado',
            cuerpo: {'estado': destino.codigo, 'fecha': hoy},
            entidadId: encargoId,
            encargoId: encargoId,
          ),
        );
        return true;
      });

  Future<Monto> _sumaTrabajos(String encargoId) async {
    final suma = _base.trabajos.precio.sum();
    final fila =
        await (_base.selectOnly(_base.trabajos)
              ..addColumns([suma])
              ..where(_base.trabajos.encargoId.equals(encargoId)))
            .getSingle();
    return Monto.desdeCentimos(fila.read(suma) ?? 0);
  }

  static Encargo _aEncargo(EncargoFila fila, ClienteFila? cliente) {
    DateTime? dia(String? iso) => iso == null ? null : diaDesdeIso(iso);
    return Encargo(
      id: fila.id,
      numero: fila.numero,
      cliente: cliente == null
          ? null
          : Cliente(
              id: cliente.id,
              nombre: cliente.nombre,
              telefono: cliente.telefono == null ? null : Telefono.e164(cliente.telefono!),
            ),
      descripcion: fila.descripcion,
      codigoEstado: fila.estado,
      precioTotal: Monto.desdeCentimos(fila.precioTotal),
      descuento: Monto.desdeCentimos(fila.descuento),
      saldoPendiente: Monto.desdeCentimos(fila.saldoPendiente),
      ubicacionFisica: fila.ubicacionFisica,
      notasGenerales: fila.notasGenerales,
      fechaEntregaPrometida: diaDesdeIso(fila.fechaEntregaPrometida),
      fechaEntregaAcordada: diaDesdeIso(fila.fechaEntregaAcordada),
      fechaListo: dia(fila.fechaListo),
      fechaEntregaReal: dia(fila.fechaEntregaReal),
    );
  }
}
