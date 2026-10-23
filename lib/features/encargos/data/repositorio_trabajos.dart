import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/domain/monto.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/infrastructure/db/base_datos.dart';
import '../../../shared/sync/colecciones.dart';
import '../../../shared/sync/outbox.dart';
import '../../../shared/sync/recalculo.dart';
import '../../servicios/domain/servicio.dart';
import '../domain/trabajo.dart';
import 'estado_local.dart';

abstract final class TiposTrabajo {
  static const crear = 'crear_trabajo';
  static const editar = 'editar_trabajo';
  static const eliminar = 'eliminar_trabajo';
}

/// Valor por defecto de `objetoId` en [RepositorioTrabajos.editar]: no
/// tocar el vínculo (un `null` explícito lo quita).
const _mismoObjeto = Object();

/// Los trabajos de un encargo (S3b1). Cada escritura, en una transacción:
/// el trabajo en Drift, el recálculo local del total y el saldo
/// ([recalcularTotales]) y la operación en el Outbox.
///
/// Un encargo entregado o cancelado no cambia sus trabajos (decisión del
/// usuario); el backend lo permitiría, la app no.
///
/// Un trabajo puede vincularse a un objeto recibido del mismo encargo (S3d2,
/// Caso 6); el vínculo solo viaja si hay uno o si cambió.
class RepositorioTrabajos {
  RepositorioTrabajos({
    required this._base,
    required this._outbox,
    String Function()? nuevoId,
    DateTime Function()? reloj,
  }) : _nuevoId = nuevoId ?? const Uuid().v4,
       _reloj = reloj ?? DateTime.now;

  final BaseDatos _base;
  final Outbox _outbox;
  final String Function() _nuevoId;
  final DateTime Function() _reloj;

  /// En el orden en que se agregaron.
  Stream<List<Trabajo>> observar(String encargoId) {
    final consulta = _base.select(_base.trabajos)
      ..where((t) => t.encargoId.equals(encargoId))
      ..orderBy([(t) => OrderingTerm.asc(t.creadoEn), (t) => OrderingTerm.asc(t.id)]);
    return consulta.map(_aTrabajo).watch();
  }

  /// Desde el catálogo: se copian nombre y precio (Doc 2, regla 12) y al
  /// servidor solo viaja el `servicio_id`, que él copia igual.
  Future<Trabajo> agregarDelCatalogo(
    String encargoId,
    Servicio servicio, {
    String? objetoId,
  }) async {
    if (!servicio.activo) {
      throw const ValorInvalido(
        'SERVICIO_NO_DISPONIBLE',
        'Ese servicio está desactivado en el catálogo.',
      );
    }
    final id = _nuevoId();
    return _agregar(
      Trabajo(
        id: id,
        encargoId: encargoId,
        servicioId: servicio.id,
        objetoRecibidoId: objetoId,
        descripcion: servicio.nombre,
        precio: servicio.precio,
      ),
      {'id': id, 'servicio_id': servicio.id, 'objeto_recibido_id': ?objetoId},
    );
  }

  Future<Trabajo> agregarPersonalizado(
    String encargoId, {
    required String descripcion,
    required Monto precio,
    String? objetoId,
  }) async {
    final limpia = ReglasTrabajo.validarDescripcion(descripcion);
    final valido = ReglasTrabajo.validarPrecio(precio);
    final id = _nuevoId();
    return _agregar(
      Trabajo(
        id: id,
        encargoId: encargoId,
        servicioId: null,
        objetoRecibidoId: objetoId,
        descripcion: limpia,
        precio: valido,
      ),
      {'id': id, 'descripcion': limpia, 'precio': valido.soles, 'objeto_recibido_id': ?objetoId},
    );
  }

  Future<Trabajo> _agregar(Trabajo trabajo, Json cuerpo) => _base.transaction(() async {
    await _comprobarAbierto(trabajo.encargoId);
    await _comprobarObjeto(trabajo.encargoId, trabajo.objetoRecibidoId);
    await _base
        .into(_base.trabajos)
        .insert(
          TrabajosCompanion.insert(
            id: trabajo.id,
            creadoEn: _reloj().toUtc().toIso8601String(),
            actualizadoEn: sinVersionDelServidor,
            encargoId: trabajo.encargoId,
            servicioId: Value(trabajo.servicioId),
            objetoRecibidoId: Value(trabajo.objetoRecibidoId),
            descripcion: trabajo.descripcion,
            precio: trabajo.precio.centimos,
          ),
        );
    await recalcularTotales(_base, trabajo.encargoId);
    await _outbox.encolar(
      OperacionNueva(
        tipo: TiposTrabajo.crear,
        metodo: 'POST',
        ruta: '/encargos/${trabajo.encargoId}/trabajos',
        cuerpo: cuerpo,
        entidadId: trabajo.id,
        encargoId: trabajo.encargoId,
      ),
    );
    return trabajo;
  });

  /// `PATCH` solo con lo que cambió; sin cambios no encola nada y devuelve
  /// `false`. En un trabajo del catálogo el precio no se toca (`422
  /// TRABAJO_PRECIO_BLOQUEADO` en el backend). Sin `objetoId` el vínculo
  /// queda como está; con `null` se quita.
  Future<bool> editar(
    Trabajo actual, {
    required String descripcion,
    Monto? precio,
    Object? objetoId = _mismoObjeto,
  }) async {
    final limpia = ReglasTrabajo.validarDescripcion(descripcion);
    if (precio != null && precio != actual.precio && actual.delCatalogo) {
      throw const ValorInvalido(
        'TRABAJO_PRECIO_BLOQUEADO',
        'El precio de un trabajo del catálogo no se cambia.',
      );
    }
    final nuevoPrecio = precio == null ? null : ReglasTrabajo.validarPrecio(precio);
    final nuevoObjeto = identical(objetoId, _mismoObjeto)
        ? actual.objetoRecibidoId
        : objetoId as String?;
    final cuerpo = <String, Object?>{
      if (limpia != actual.descripcion) 'descripcion': limpia,
      if (nuevoPrecio != null && nuevoPrecio != actual.precio) 'precio': nuevoPrecio.soles,
      if (nuevoObjeto != actual.objetoRecibidoId) 'objeto_recibido_id': nuevoObjeto,
    };
    if (cuerpo.isEmpty) return false;
    return _base.transaction(() async {
      await _comprobarAbierto(actual.encargoId);
      if (nuevoObjeto != actual.objetoRecibidoId) {
        await _comprobarObjeto(actual.encargoId, nuevoObjeto);
      }
      final filas = await (_base.update(_base.trabajos)..where((t) => t.id.equals(actual.id)))
          .write(
            TrabajosCompanion(
              descripcion: Value(limpia),
              precio: Value((nuevoPrecio ?? actual.precio).centimos),
              objetoRecibidoId: Value(nuevoObjeto),
            ),
          );
      if (filas == 0) throw StateError('No existe el trabajo ${actual.id}');
      await recalcularTotales(_base, actual.encargoId);
      await _outbox.encolar(
        OperacionNueva(
          tipo: TiposTrabajo.editar,
          metodo: 'PATCH',
          ruta: '/encargos/${actual.encargoId}/trabajos/${actual.id}',
          cuerpo: cuerpo,
          entidadId: actual.id,
          encargoId: actual.encargoId,
        ),
      );
      return true;
    });
  }

  /// Se borra la fila (en local no hay tombstones) con sus materiales, como
  /// la cascada del backend (Doc 5 v1.5). Si la suma baja del descuento, el
  /// recálculo lo ajusta igual que el servidor.
  Future<void> eliminar(Trabajo trabajo) => _base.transaction(() async {
    await _comprobarAbierto(trabajo.encargoId);
    await (_base.delete(_base.materiales)..where((m) => m.trabajoId.equals(trabajo.id))).go();
    await (_base.delete(_base.trabajos)..where((t) => t.id.equals(trabajo.id))).go();
    await recalcularTotales(_base, trabajo.encargoId);
    await _outbox.encolar(
      OperacionNueva(
        tipo: TiposTrabajo.eliminar,
        metodo: 'DELETE',
        ruta: '/encargos/${trabajo.encargoId}/trabajos/${trabajo.id}',
        entidadId: trabajo.id,
        encargoId: trabajo.encargoId,
      ),
    );
  });

  Future<void> _comprobarAbierto(String encargoId) async {
    if ((await leerEstadoLocal(_base, encargoId))?.cerrado ?? false) {
      throw const ValorInvalido(
        'ENCARGO_CERRADO',
        'Un encargo entregado o cancelado no cambia sus trabajos.',
      );
    }
  }

  /// El objeto tiene que existir en este encargo (`422
  /// OBJETO_NO_EN_ENCARGO` en el backend).
  Future<void> _comprobarObjeto(String encargoId, String? objetoId) async {
    if (objetoId == null) return;
    final objeto = await (_base.select(
      _base.objetosRecibidos,
    )..where((o) => o.id.equals(objetoId) & o.encargoId.equals(encargoId))).getSingleOrNull();
    if (objeto == null) {
      throw const ValorInvalido('OBJETO_NO_EN_ENCARGO', 'Ese objeto ya no está en el encargo.');
    }
  }

  static Trabajo _aTrabajo(TrabajoFila fila) => Trabajo(
    id: fila.id,
    encargoId: fila.encargoId,
    servicioId: fila.servicioId,
    objetoRecibidoId: fila.objetoRecibidoId,
    descripcion: fila.descripcion,
    precio: Monto.desdeCentimos(fila.precio),
  );
}
