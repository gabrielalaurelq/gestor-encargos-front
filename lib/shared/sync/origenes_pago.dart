import 'package:drift/drift.dart';

import '../infrastructure/db/base_datos.dart';
import '../infrastructure/http/cliente_api.dart';
import 'colecciones.dart';

/// Baja el catálogo de orígenes de pago (Doc 7 v1.3). No viaja en `/sync`
/// porque es del sistema y no del negocio.
///
/// Se pide **una vez por arranque de la app** y, además, cada vez que la tabla
/// esté vacía (primer uso, u otra cuenta tras cerrar sesión). Son cuatro filas
/// que casi nunca cambian: pedirlas en cada vuelta sería gastar datos.
class OrigenesPagoRemotos {
  OrigenesPagoRemotos({required this._base, required this._api});

  final BaseDatos _base;
  final ClienteApi _api;
  bool _bajadosEnEsteArranque = false;

  Future<void> actualizarSiHaceFalta() async {
    if (_bajadosEnEsteArranque && !await _vacia()) return;
    final lista = (await _api.get('/origenes-pago') as List).cast<Json>();
    // Entera y en una transacción: nunca se ve el catálogo a medias.
    await _base.transaction(() async {
      await _base.delete(_base.origenesPago).go();
      await _base.batch(
        (lote) => lote.insertAll(_base.origenesPago, [
          for (final origen in lista)
            OrigenesPagoCompanion.insert(
              id: Value(origen['id']! as int),
              nombre: origen['nombre']! as String,
              activo: origen['activo']! as bool,
            ),
        ]),
      );
    });
    _bajadosEnEsteArranque = true;
  }

  Future<bool> _vacia() async {
    final fila = await (_base.select(_base.origenesPago)..limit(1)).getSingleOrNull();
    return fila == null;
  }
}
