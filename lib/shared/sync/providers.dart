import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../infrastructure/providers.dart';
import 'bajada.dart';
import 'descarte.dart';
import 'motor_sync.dart';
import 'numeracion.dart';
import 'outbox.dart';
import 'subida.dart';

part 'providers.g.dart';

// Grafo del motor de sincronización (Doc 7, Bloque 3: `shared/sync/`).

@Riverpod(keepAlive: true)
Outbox outbox(Ref ref) {
  final outbox = Outbox(ref.watch(baseDatosProvider));
  ref.onDispose(outbox.cerrar);
  return outbox;
}

@Riverpod(keepAlive: true)
Numeracion numeracion(Ref ref) =>
    Numeracion(base: ref.watch(baseDatosProvider), api: ref.watch(clienteApiProvider));

@Riverpod(keepAlive: true)
Bajada bajada(Ref ref) => Bajada(
  api: ref.watch(clienteApiProvider),
  base: ref.watch(baseDatosProvider),
  idsProtegidos: ref.watch(outboxProvider).idsProtegidos,
);

@Riverpod(keepAlive: true)
Subida subida(Ref ref) => Subida(
  api: ref.watch(clienteApiProvider),
  outbox: ref.watch(outboxProvider),
  preparar: ref.watch(numeracionProvider).numerarSiFalta,
);

/// El motor, con sus disparadores automáticos conectados: red recuperada y
/// operación encolada. Los de sesión (entrar, abrir la app) los dispara la
/// feature de sesión, y volver al primer plano, `app.dart`.
@Riverpod(keepAlive: true)
MotorSync motorSync(Ref ref) {
  final motor = MotorSync(
    bajada: ref.watch(bajadaProvider),
    subida: ref.watch(subidaProvider),
    numeracion: ref.watch(numeracionProvider),
    tokens: ref.watch(almacenTokensProvider),
  );
  final disparadores = [
    ref.watch(conectividadProvider).recuperada.listen((_) => unawaited(motor.sincronizar())),
    ref.watch(outboxProvider).encoladas.listen((_) => unawaited(motor.sincronizar())),
  ];
  ref.onDispose(() {
    for (final disparador in disparadores) {
      unawaited(disparador.cancel());
    }
    motor.cerrar();
  });
  return motor;
}

/// Estado de la sincronización para un ícono discreto (Doc 7, Bloque 3).
@riverpod
Stream<EstadoSync> syncStatus(Ref ref) async* {
  final motor = ref.watch(motorSyncProvider);
  yield motor.estado;
  yield* motor.estados;
}

/// Cuántas operaciones esperan subir. Lo consume el cierre de sesión: con
/// cambios sin enviar **no se deja cerrar** (decisión del usuario, F2) —
/// cerrar sesión borra la base local, y con ella esos cambios.
@Riverpod(keepAlive: true)
Stream<int> cambiosPendientes(Ref ref) => ref.watch(outboxProvider).pendientes();

/// Las operaciones que el servidor rechazó (lista de "no sincronizadas").
@riverpod
Stream<List<OperacionApartada>> operacionesApartadas(Ref ref) =>
    ref.watch(outboxProvider).apartadas();

/// "Descartar" una operación apartada (Doc 7 v1.2).
@Riverpod(keepAlive: true)
Descarte descarte(Ref ref) =>
    Descarte(base: ref.watch(baseDatosProvider), api: ref.watch(clienteApiProvider));
