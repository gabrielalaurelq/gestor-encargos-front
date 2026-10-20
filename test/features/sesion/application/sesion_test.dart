import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/sesion/application/sesion.dart';
import 'package:gestor_encargos/features/sesion/domain/estado_sesion.dart';
import 'package:gestor_encargos/shared/infrastructure/providers.dart';

import '../../../helpers/adaptador_falso.dart';
import '../../../helpers/entorno_prueba.dart';

void main() {
  late EntornoPrueba entorno;
  late ProviderContainer contenedor;

  void crear(EntornoPrueba nuevo) {
    entorno = nuevo;
    contenedor = ProviderContainer(overrides: entorno.overrides);
  }

  tearDown(() async {
    contenedor.dispose();
    await entorno.cerrar();
  });

  Sesion sesion() => contenedor.read(sesionProvider.notifier);

  group('al arrancar', () {
    test('sin tokens guardados → anónima', () async {
      crear(EntornoPrueba());

      expect(await sesionCargada(contenedor), EstadoSesion.anonima);
    });

    test('con tokens → iniciada, sin pedir nada a la red (offline-first)', () async {
      crear(EntornoPrueba.conSesion());

      expect(await sesionCargada(contenedor), EstadoSesion.iniciada);
      expect(entorno.backend.peticiones, isEmpty);
    });

    test('con tokens → arranca una sincronización', () async {
      crear(EntornoPrueba.conSesion());

      await sesionCargada(contenedor);

      expect(entorno.motor.sincronizaciones, 1);
    });

    test('sin tokens → no sincroniza', () async {
      crear(EntornoPrueba());

      await sesionCargada(contenedor);

      expect(entorno.motor.sincronizaciones, 0);
    });

    test(
      'con tokens → re-registra el token de notificaciones (pudo rotar con la app cerrada)',
      () async {
        crear(EntornoPrueba.conSesion());
        entorno.notificaciones.token = 'fcm-1';
        entorno.backend.cuando('POST /dispositivos/fcm-token', (_) => const Respuesta(204));

        await sesionCargada(contenedor);
        await pumpEventQueue();

        expect(entorno.backend.peticiones.single.cuerpo, {'fcm_token': 'fcm-1'});
      },
    );
  });

  group('iniciar sesión', () {
    setUp(() => crear(EntornoPrueba()));

    test('canjea el ID token de Google, guarda los tokens y queda iniciada', () async {
      entorno.loginAceptado();
      await sesionCargada(contenedor);

      expect(await sesion().iniciarSesion(), isNull);

      expect(entorno.backend.peticiones.single.cuerpo, {'id_token': 'id-token-google'});
      expect((await entorno.tokens.leer())!.refresh, 'refresh-1');
      expect(contenedor.read(sesionProvider), EstadoSesion.iniciada);
    });

    test('al entrar sincroniza (reserva números y trae los datos del negocio)', () async {
      entorno.loginAceptado();
      await sesionCargada(contenedor);

      await sesion().iniciarSesion();

      expect(entorno.motor.sincronizaciones, 1);
    });

    test('registra el token de notificaciones justo después (Doc 5)', () async {
      entorno.loginAceptado();
      entorno.notificaciones.token = 'fcm-1';
      entorno.backend.cuando('POST /dispositivos/fcm-token', (p) {
        expect(p.autorizacion, 'Bearer access-1');
        return const Respuesta(204);
      });
      await sesionCargada(contenedor);

      await sesion().iniciarSesion();
      await pumpEventQueue();

      expect(entorno.backend.contar('POST /dispositivos/fcm-token'), 1);
    });

    test('un fallo al registrar las notificaciones no impide entrar', () async {
      entorno.loginAceptado();
      entorno.notificaciones.token = 'fcm-1';
      entorno.backend.cuando(
        'POST /dispositivos/fcm-token',
        (_) => Respuesta.error(409, 'FCM_TOKEN_EN_USO'),
      );
      await sesionCargada(contenedor);

      expect(await sesion().iniciarSesion(), isNull);
      await pumpEventQueue();

      expect(contenedor.read(sesionProvider), EstadoSesion.iniciada);
    });

    test('cerrar el selector de cuentas no es un fallo: no pasa nada', () async {
      entorno.identidad.idToken = null;
      await sesionCargada(contenedor);

      expect(await sesion().iniciarSesion(), isNull);

      expect(entorno.backend.peticiones, isEmpty);
      expect(contenedor.read(sesionProvider), EstadoSesion.anonima);
    });

    test('sin red → sinConexion, sin tokens', () async {
      entorno.backend.sinRed = true;
      await sesionCargada(contenedor);

      expect(await sesion().iniciarSesion(), FalloLogin.sinConexion);
      expect(await entorno.tokens.leer(), isNull);
      expect(contenedor.read(sesionProvider), EstadoSesion.anonima);
    });

    test('cada respuesta del backend tiene su fallo', () async {
      await sesionCargada(contenedor);
      final casos = {
        Respuesta.error(401, 'ID_TOKEN_INVALIDO'): FalloLogin.rechazado,
        Respuesta.error(429, 'DEMASIADAS_PETICIONES'): FalloLogin.demasiadosIntentos,
        Respuesta.error(500, 'ERROR_INTERNO'): FalloLogin.servidor,
      };
      for (final MapEntry(key: respuesta, value: fallo) in casos.entries) {
        entorno.backend.cuando('POST /auth/login', (_) => respuesta);

        expect(await sesion().iniciarSesion(), fallo);
      }
    });

    test('build sin Firebase → noDisponible', () async {
      entorno.identidad.disponible = false;
      await sesionCargada(contenedor);

      expect(await sesion().iniciarSesion(), FalloLogin.noDisponible);
    });

    test('entra otra cuenta → borra los datos locales del negocio anterior', () async {
      await entorno.base.guardarMetadato('sesion.negocio_id', 'negocio-anterior');
      await entorno.base.guardarMetadato('sync.since', '2026-10-01T00:00:00.000Z');
      entorno.loginAceptado(negocioId: 'negocio-nuevo');
      await sesionCargada(contenedor);

      await sesion().iniciarSesion();

      expect(await entorno.base.leerMetadato('sync.since'), isNull);
      expect(await entorno.base.leerMetadato('sesion.negocio_id'), 'negocio-nuevo');
    });

    test('vuelve la misma cuenta → conserva los datos (y su Outbox)', () async {
      await entorno.base.guardarMetadato('sesion.negocio_id', 'negocio-1');
      await entorno.base.guardarMetadato('sync.since', '2026-10-01T00:00:00.000Z');
      entorno.loginAceptado(negocioId: 'negocio-1');
      await sesionCargada(contenedor);

      await sesion().iniciarSesion();

      expect(await entorno.base.leerMetadato('sync.since'), '2026-10-01T00:00:00.000Z');
    });
  });

  group('cerrar sesión', () {
    setUp(() => crear(EntornoPrueba.conSesion()));

    test('avisa al servidor, borra tokens y base local, y olvida la cuenta de Google', () async {
      entorno.backend.cuando('POST /auth/logout', (_) => const Respuesta(204));
      await entorno.base.guardarMetadato('sync.since', '2026-10-01T00:00:00.000Z');
      await sesionCargada(contenedor);

      expect(await sesion().cerrarSesion(), isNull);

      expect(entorno.backend.contar('POST /auth/logout'), 1);
      expect(await entorno.tokens.leer(), isNull);
      expect(await entorno.base.leerMetadato('sync.since'), isNull);
      expect(entorno.identidad.cierres, 1);
      expect(contenedor.read(sesionProvider), EstadoSesion.anonima);
    });

    test('no llama a DELETE /dispositivos/fcm-token: el logout ya borra el dispositivo', () async {
      entorno.backend.cuando('POST /auth/logout', (_) => const Respuesta(204));
      await sesionCargada(contenedor);

      await sesion().cerrarSesion();

      expect(entorno.backend.peticiones.map((p) => p.ruta), ['/auth/logout']);
    });

    test('con cambios sin enviar → no cierra ni toca nada (decisión del usuario)', () async {
      entorno.pendientes = 3;
      contenedor.dispose();
      contenedor = ProviderContainer(overrides: entorno.overrides);
      await sesionCargada(contenedor);

      final fallo = await sesion().cerrarSesion();

      expect(fallo, isA<CierreConPendientes>().having((f) => f.cantidad, 'cantidad', 3));
      expect(entorno.backend.peticiones, isEmpty);
      expect(await entorno.tokens.leer(), isNotNull);
      expect(contenedor.read(sesionProvider), EstadoSesion.iniciada);
    });

    test('sin red → no cierra: la sesión seguiría viva en el servidor', () async {
      entorno.backend.sinRed = true;
      await sesionCargada(contenedor);

      expect(await sesion().cerrarSesion(), isA<CierreSinConexion>());
      expect(await entorno.tokens.leer(), isNotNull);
      expect(contenedor.read(sesionProvider), EstadoSesion.iniciada);
    });

    test('error del servidor → no cierra', () async {
      entorno.backend.cuando('POST /auth/logout', (_) => Respuesta.error(503, 'NO_DISPONIBLE'));
      await sesionCargada(contenedor);

      expect(await sesion().cerrarSesion(), isA<CierreFallido>());
      expect(await entorno.tokens.leer(), isNotNull);
    });

    test('la sesión ya no existía en el servidor → termina de cerrar en el teléfono', () async {
      entorno.backend.cuando('POST /auth/logout', (_) => Respuesta.error(401, 'TOKEN_EXPIRADO'));
      entorno.backend.cuando('POST /auth/refresh', (_) => Respuesta.error(401, 'SESION_INVALIDA'));
      await entorno.base.guardarMetadato('sync.since', '2026-10-01T00:00:00.000Z');
      await sesionCargada(contenedor);

      expect(await sesion().cerrarSesion(), isNull);

      expect(await entorno.base.leerMetadato('sync.since'), isNull);
      expect(contenedor.read(sesionProvider), EstadoSesion.anonima);
    });
  });

  group('sesión expirada (refresh rechazado)', () {
    setUp(() => crear(EntornoPrueba.conSesion()));

    test('vuelve a anónima pero conserva los datos locales', () async {
      entorno.backend.cuando('GET /negocio', (_) => Respuesta.error(401, 'TOKEN_EXPIRADO'));
      entorno.backend.cuando('POST /auth/refresh', (_) => Respuesta.error(401, 'SESION_INVALIDA'));
      await entorno.base.guardarMetadato('sync.since', '2026-10-01T00:00:00.000Z');
      await sesionCargada(contenedor);

      await expectLater(contenedor.read(clienteApiProvider).get('/negocio'), throwsA(anything));

      expect(contenedor.read(sesionProvider), EstadoSesion.anonima);
      expect(await entorno.base.leerMetadato('sync.since'), '2026-10-01T00:00:00.000Z');
    });
  });

  group('rotación del token de notificaciones', () {
    test('con sesión → se registra el nuevo', () async {
      crear(EntornoPrueba.conSesion());
      entorno.backend.cuando('POST /dispositivos/fcm-token', (_) => const Respuesta(204));
      await sesionCargada(contenedor);

      entorno.notificaciones.rotar('fcm-2');
      await pumpEventQueue();

      expect(entorno.backend.peticiones.single.cuerpo, {'fcm_token': 'fcm-2'});
    });

    test('sin sesión → se ignora (no hay a quién asociarlo)', () async {
      crear(EntornoPrueba());
      await sesionCargada(contenedor);

      entorno.notificaciones.rotar('fcm-2');
      await pumpEventQueue();

      expect(entorno.backend.peticiones, isEmpty);
    });
  });
}
