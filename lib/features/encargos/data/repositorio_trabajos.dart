import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/domain/monto.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/infrastructure/db/base_datos.dart';
import '../../../shared/sync/colecciones.dart';
import '../../../shared/sync/outbox.dart';
import '../../../shared/sync/recalculo.dart';
import '../../servicios/domain/servicio.dart';
import '../domain/estado_encargo.dart';
import '../domain/trabajo.dart';

abstract final class TiposTrabajo {
  static const crear = 'crear_trabajo';
  static const editar = 'editar_trabajo';
  static const eliminar = 'eliminar_trabajo';
}

/// Los trabajos de un encargo (S3b1). Cada escritura, en una transacción:
/// el trabajo en Drift, el recálculo local del total y el saldo
/// ([recalcularTotales]) y la operación en el Outbox.
///
/// Un encargo entregado o cancelado no cambia sus trabajos (decisión del
/// usuario); el backend lo permitiría, la app no.
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
  Future<Trabajo> agregarDelCatalogo(String encargoId, Servicio servicio) async {
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
        descripcion: servicio.nombre,
        precio: servicio.precio,
      ),
      {'id': id, 'servicio_id': servicio.id},
    );
  }

  Future<Trabajo> agregarPersonalizado(
    String encargoId, {
    required String descripcion,
    required Monto precio,
  }) async {
    final limpia = ReglasTrabajo.validarDescripcion(descripcion);
    final valido = ReglasTrabajo.validarPrecio(precio);
    final id = _nuevoId();
    return _agregar(
      Trabajo(id: id, encargoId: encargoId, servicioId: null, descripcion: limpia, precio: valido),
      {'id': id, 'descripcion': limpia, 'precio': valido.soles},
    );
  }

  Future<Trabajo> _agregar(Trabajo trabajo, Json cuerpo) => _base.transaction(() async {
    await _comprobarAbierto(trabajo.encargoId);
    await _base
        .into(_base.trabajos)
        .insert(
          TrabajosCompanion.insert(
            id: trabajo.id,
            creadoEn: _reloj().toUtc().toIso8601String(),
            actualizadoEn: sinVersionDelServidor,
            encargoId: trabajo.encargoId,
            servicioId: Value(trabajo.servicioId),
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
  /// TRABAJO_PRECIO_BLOQUEADO` en el backend).
  Future<bool> editar(Trabajo actual, {required String descripcion, Monto? precio}) async {
    final limpia = ReglasTrabajo.validarDescripcion(descripcion);
    if (precio != null && precio != actual.precio && actual.delCatalogo) {
      throw const ValorInvalido(
        'TRABAJO_PRECIO_BLOQUEADO',
        'El precio de un trabajo del catálogo no se cambia.',
      );
    }
    final nuevoPrecio = precio == null ? null : ReglasTrabajo.validarPrecio(precio);
    final cuerpo = <String, Object?>{
      if (limpia != actual.descripcion) 'descripcion': limpia,
      if (nuevoPrecio != null && nuevoPrecio != actual.precio) 'precio': nuevoPrecio.soles,
    };
    if (cuerpo.isEmpty) return false;
    return _base.transaction(() async {
      await _comprobarAbierto(actual.encargoId);
      final filas = await (_base.update(_base.trabajos)..where((t) => t.id.equals(actual.id)))
          .write(
            TrabajosCompanion(
              descripcion: Value(limpia),
              precio: Value((nuevoPrecio ?? actual.precio).centimos),
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
    final estado =
        await (_base.selectOnly(_base.encargos)
              ..addColumns([_base.encargos.estado])
              ..where(_base.encargos.id.equals(encargoId)))
            .map((fila) => fila.read(_base.encargos.estado))
            .getSingleOrNull();
    if (estado == null) throw StateError('No existe el encargo $encargoId');
    if (EstadoEncargo.desde(estado)?.cerrado ?? false) {
      throw const ValorInvalido(
        'ENCARGO_CERRADO',
        'Un encargo entregado o cancelado no cambia sus trabajos.',
      );
    }
  }

  static Trabajo _aTrabajo(TrabajoFila fila) => Trabajo(
    id: fila.id,
    encargoId: fila.encargoId,
    servicioId: fila.servicioId,
    descripcion: fila.descripcion,
    precio: Monto.desdeCentimos(fila.precio),
  );
}
