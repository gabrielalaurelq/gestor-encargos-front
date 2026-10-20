import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/domain/monto.dart';
import '../../../shared/infrastructure/db/base_datos.dart';
import '../../../shared/sync/outbox.dart';
import '../domain/servicio.dart';

abstract final class TiposServicio {
  static const crear = 'crear_servicio';
  static const editar = 'editar_servicio';
}

/// El Catálogo de servicios en la base local (Doc 7, Bloque 3): cada escritura
/// va a Drift y encola su envío **en la misma transacción**. La UI nunca
/// espera a la red; el motor de sync sube la operación cuando puede.
class RepositorioServicios {
  RepositorioServicios({
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

  /// Todos, activos y desactivados, por nombre sin distinguir mayúsculas.
  Stream<List<Servicio>> observar() {
    final consulta = _base.select(_base.servicios)
      ..orderBy([(s) => OrderingTerm.asc(s.nombre.collate(Collate.noCase))]);
    return consulta.map(_aServicio).watch();
  }

  Future<Servicio> crear({required String nombre, required Monto precio}) async {
    final servicio = Servicio(
      id: _nuevoId(),
      nombre: Servicio.validarNombre(nombre),
      precio: Servicio.validarPrecio(precio),
      activo: true,
    );
    return _base.transaction(() async {
      await _base
          .into(_base.servicios)
          .insert(
            ServiciosCompanion.insert(
              id: servicio.id,
              creadoEn: _reloj().toUtc().toIso8601String(),
              actualizadoEn: sinVersionDelServidor,
              nombre: servicio.nombre,
              precio: servicio.precio.centimos,
              activo: true,
            ),
          );
      // El id viaja en el alta: si se repite (se cortó la red antes de la
      // respuesta), el servidor responde 200 con el existente (Doc 5).
      await _outbox.encolar(
        OperacionNueva(
          tipo: TiposServicio.crear,
          metodo: 'POST',
          ruta: '/servicios',
          cuerpo: {'id': servicio.id, 'nombre': servicio.nombre, 'precio': servicio.precio.soles},
          entidadId: servicio.id,
        ),
      );
      return servicio;
    });
  }

  /// Rige para los trabajos que se creen desde ahora (Doc 2, invariante 12):
  /// los ya creados copiaron su precio.
  Future<void> cambiarPrecio(String id, Monto precio) async {
    final valido = Servicio.validarPrecio(precio);
    return _editar(id, ServiciosCompanion(precio: Value(valido.centimos)), {
      'precio': valido.soles,
    });
  }

  Future<void> cambiarActivo(String id, {required bool activo}) =>
      _editar(id, ServiciosCompanion(activo: Value(activo)), {'activo': activo});

  Future<void> _editar(String id, ServiciosCompanion cambio, Map<String, Object?> cuerpo) =>
      _base.transaction(() async {
        // Sin tocar `actualizado_en` (ver `sinVersionDelServidor`).
        final filas = await (_base.update(
          _base.servicios,
        )..where((s) => s.id.equals(id))).write(cambio);
        if (filas == 0) throw StateError('No existe el servicio $id');
        await _outbox.encolar(
          OperacionNueva(
            tipo: TiposServicio.editar,
            metodo: 'PATCH',
            ruta: '/servicios/$id',
            cuerpo: cuerpo,
            entidadId: id,
          ),
        );
      });

  static Servicio _aServicio(ServicioFila fila) => Servicio(
    id: fila.id,
    nombre: fila.nombre,
    precio: Monto.desdeCentimos(fila.precio),
    activo: fila.activo,
  );
}
