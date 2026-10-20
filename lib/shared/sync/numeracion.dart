import 'dart:convert';

import 'package:drift/drift.dart';

import '../infrastructure/db/base_datos.dart';
import '../infrastructure/http/cliente_api.dart';
import 'outbox.dart';

/// Numeración de encargos por bloques — patrón Hi/Lo (Doc 3, ADR-008).
///
/// El dispositivo reserva rangos con `POST /encargos/reservar-bloque-numeros`
/// cuando tiene conexión y asigna números de ahí sin tocar la red. Puede tener
/// más de un rango: el siguiente se pide cuando al actual le quedan pocos, así
/// que conviven el que se está gastando y el de reserva.
class Numeracion {
  Numeracion({required this._base, required this._api});

  final BaseDatos _base;
  final ClienteApi _api;

  /// Rangos reservados y sin gastar: `[[siguiente, hasta], ...]`, en orden.
  static const claveRangos = 'numeracion.rangos';

  /// Con esto o menos se pide otro bloque (el Doc 3 pone de ejemplo 10). Con
  /// bloques de 100 y ~100 encargos activos por negocio, agotarlo sin
  /// conexión es casi teórico.
  static const umbral = 10;

  Future<List<List<int>>> _rangos() async {
    final texto = await _base.leerMetadato(claveRangos);
    if (texto == null) return [];
    return [
      for (final rango in jsonDecode(texto) as List) [for (final n in rango as List) n as int],
    ];
  }

  Future<void> _guardar(List<List<int>> rangos) =>
      _base.guardarMetadato(claveRangos, jsonEncode(rangos));

  Future<int> restantes() async =>
      (await _rangos()).fold<int>(0, (suma, r) => suma + r[1] - r[0] + 1);

  /// El próximo número, o `null` si se agotaron (el encargo se crea igual y
  /// se numera al subir; Doc 3, caso límite). Llamarla dentro de la
  /// transacción que crea el encargo: un número tomado y no usado es un hueco.
  Future<int?> tomar() => _base.transaction(() async {
    final rangos = await _rangos();
    if (rangos.isEmpty) return null;
    final numero = rangos.first[0];
    if (numero == rangos.first[1]) {
      rangos.removeAt(0);
    } else {
      rangos.first[0] = numero + 1;
    }
    await _guardar(rangos);
    return numero;
  });

  Future<void> reservarSiHaceFalta() async {
    if (await restantes() > umbral) return;
    final bloque = await _api.post('/encargos/reservar-bloque-numeros') as Map;
    final rangos = await _rangos()
      ..add([bloque['desde']! as int, bloque['hasta']! as int]);
    await _guardar(rangos);
  }

  /// Un encargo creado con el bloque agotado se encoló sin número. El backend
  /// no tiene forma de numerarlo después (un alta sin `numero` queda en `null`
  /// para siempre), así que **la última oportunidad es justo antes de
  /// subirlo**: el motor reservó un bloque al empezar la vuelta, con red.
  ///
  /// Se numeran a la vez la operación y la fila local, en una transacción.
  Future<OperacionOutbox> numerarSiFalta(OperacionOutbox operacion) async {
    if (operacion.tipo != TiposOperacion.crearEncargo) return operacion;
    final cuerpo = operacion.cuerpoJson ?? {};
    if (cuerpo['numero'] != null) return operacion;

    return _base.transaction(() async {
      final numero = await tomar();
      if (numero == null) return operacion;
      final nuevo = {...cuerpo, 'numero': numero};
      await (_base.update(_base.operacionesOutbox)..where((o) => o.id.equals(operacion.id))).write(
        OperacionesOutboxCompanion(cuerpo: Value(jsonEncode(nuevo))),
      );
      await (_base.update(_base.encargos)..where((e) => e.id.equals(operacion.entidadId))).write(
        EncargosCompanion(numero: Value(numero)),
      );
      return operacion.copyWith(cuerpo: Value(jsonEncode(nuevo)));
    });
  }
}
