import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/domain/dia.dart';
import '../../../shared/domain/monto.dart';
import '../../../shared/domain/telefono.dart';
import '../../../shared/infrastructure/db/base_datos.dart';
import '../../../shared/sync/numeracion.dart';
import '../../../shared/sync/outbox.dart';
import '../../clientes/domain/cliente.dart';
import '../domain/encargo.dart';
import '../domain/encargo_nuevo.dart';
import '../domain/estado_encargo.dart';

/// Los encargos en la base local. Mismo patrón que clientes y catálogo: cada
/// escritura va a Drift y encola su envío en la misma transacción, sin
/// adelantar `actualizado_en` (ver `sinVersionDelServidor`).
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
          tipo: TiposOperacion.crearEncargo,
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
