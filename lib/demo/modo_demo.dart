import 'package:drift/drift.dart';
import 'package:flutter_riverpod/misc.dart';

import '../features/sesion/application/sesion.dart';
import '../shared/infrastructure/auth/almacen_tokens.dart';
import '../shared/infrastructure/db/base_datos.dart';
import '../shared/infrastructure/providers.dart';
import '../shared/sync/motor_sync.dart';
import '../shared/sync/numeracion.dart';
import '../shared/sync/providers.dart';

/// Build de demostración (`--dart-define=DEMO=true`): la app sin servidor,
/// para probar el uso diario en un teléfono antes de que existan Firebase y
/// el backend de staging. Entra sin login, no sincroniza nunca y numera los
/// encargos en el teléfono. **Lo que se carga en ella no se sube jamás.**
const modoDemo = bool.fromEnvironment('DEMO');

/// Lo que cambia frente al build real: una sesión que ya está abierta y un
/// motor de sync que no hace nada. Nada más toca la red sin acción del
/// usuario.
List<Override> overridesDemo() => [
  almacenTokensProvider.overrideWithValue(
    AlmacenTokensEnMemoria(const Tokens(access: 'demo', refresh: 'demo')),
  ),
  motorSyncProvider.overrideWithValue(MotorSyncDemo()),
];

/// Lo que en el build real llega del servidor al entrar: el catálogo de
/// orígenes de pago, un rango de números y el nombre del negocio. Solo si
/// falta, así que abrir la app otra vez no pisa nada.
Future<void> prepararDemo(BaseDatos base) async {
  final origen = await (base.select(base.origenesPago)..limit(1)).getSingleOrNull();
  if (origen == null) {
    await base.batch(
      (lote) => lote.insertAll(base.origenesPago, [
        for (final (id, nombre) in [
          (1, 'Efectivo'),
          (2, 'Transferencia'),
          (3, 'Yape'),
          (4, 'Plin'),
        ])
          OrigenesPagoCompanion.insert(id: Value(id), nombre: nombre, activo: true),
      ]),
    );
  }
  if (await base.leerMetadato(Numeracion.claveRangos) == null) {
    await base.guardarMetadato(Numeracion.claveRangos, '[[1,999999]]');
  }
  if (await base.leerMetadato(claveNombreNegocio) == null) {
    await base.guardarMetadato(claveNombreNegocio, 'Negocio de prueba');
  }
}

class MotorSyncDemo implements MotorSync {
  @override
  Future<void> sincronizar() async {}

  @override
  EstadoSync get estado => const EstadoSync();

  @override
  Stream<EstadoSync> get estados => const Stream.empty();

  @override
  void cerrar() {}
}
