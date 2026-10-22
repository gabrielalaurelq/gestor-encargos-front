import '../../../shared/infrastructure/db/base_datos.dart';
import '../domain/estado_encargo.dart';

/// El estado del encargo según Drift, para las reglas de los hijos (qué se
/// puede cambiar en un entregado o cancelado). Se lee dentro de la
/// transacción de la escritura, nunca de lo que mostraba la pantalla.
///
/// Lanza [StateError] si el encargo no está en el teléfono: la pantalla solo
/// ofrece escribir sobre uno que existe. `null` = un estado que esta versión
/// de la app no conoce.
Future<EstadoEncargo?> leerEstadoLocal(BaseDatos base, String encargoId) async {
  final estado =
      await (base.selectOnly(base.encargos)
            ..addColumns([base.encargos.estado])
            ..where(base.encargos.id.equals(encargoId)))
          .map((fila) => fila.read(base.encargos.estado))
          .getSingleOrNull();
  if (estado == null) throw StateError('No existe el encargo $encargoId');
  return EstadoEncargo.desde(estado);
}
