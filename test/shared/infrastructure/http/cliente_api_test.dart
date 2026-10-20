import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/infrastructure/auth/almacen_tokens.dart';
import 'package:gestor_encargos/shared/infrastructure/config/ambiente.dart';
import 'package:gestor_encargos/shared/infrastructure/http/cliente_api.dart';
import 'package:gestor_encargos/shared/infrastructure/http/error_api.dart';

import '../../../helpers/adaptador_falso.dart';

void main() {
  late AdaptadorFalso backend;
  late AlmacenTokensEnMemoria tokens;
  late ClienteApi api;
  late int sesionesExpiradas;

  setUp(() {
    backend = AdaptadorFalso();
    tokens = AlmacenTokensEnMemoria(const Tokens(access: 'access-1', refresh: 'refresh-1'));
    sesionesExpiradas = 0;
    api = ClienteApi(
      ambiente: const Ambiente(apiUrl: 'http://api.test/api/v1'),
      tokens: tokens,
      adaptador: backend,
      alExpirarSesion: () => sesionesExpiradas++,
    );
  });

  /// El backend falso acepta solo el access token vigente, como el real.
  void protegerConToken(String metodoYRuta, String accessValido, Object? cuerpo) {
    backend.cuando(metodoYRuta, (p) {
      return p.autorizacion == 'Bearer $accessValido'
          ? Respuesta(200, cuerpo)
          : Respuesta.error(401, 'TOKEN_EXPIRADO');
    });
  }

  group('token de acceso', () {
    test('lo pone en cada petición autenticada', () async {
      protegerConToken('GET /negocio', 'access-1', {'id': 'n1'});

      expect(await api.get('/negocio'), {'id': 'n1'});
      expect(backend.peticiones.single.autorizacion, 'Bearer access-1');
    });

    test('no lo pone en /auth/login ni /auth/refresh', () async {
      backend.cuando('POST /auth/login', (_) => const Respuesta(200, {'access_token': 'x'}));

      await api.post('/auth/login', cuerpo: {'id_token': 'google'});

      expect(backend.peticiones.single.autorizacion, isNull);
    });
  });

  group('renovación del token en un 401', () {
    test('renueva con el refresh token, guarda el access nuevo y repite la petición', () async {
      protegerConToken('GET /negocio', 'access-2', {'id': 'n1'});
      backend.cuando('POST /auth/refresh', (p) {
        expect(p.cuerpo, {'refresh_token': 'refresh-1'});
        return const Respuesta(200, {'access_token': 'access-2'});
      });

      expect(await api.get('/negocio'), {'id': 'n1'});
      expect((await tokens.leer())!.access, 'access-2');
      expect((await tokens.leer())!.refresh, 'refresh-1', reason: 'sin rotación (Doc 5)');
    });

    test('varias peticiones con 401 a la vez → un solo refresh', () async {
      protegerConToken('GET /negocio', 'access-2', {'ok': true});
      protegerConToken('GET /clientes', 'access-2', {'ok': true});
      protegerConToken('GET /servicios', 'access-2', {'ok': true});
      backend.cuando(
        'POST /auth/refresh',
        (_) => const Respuesta(200, {'access_token': 'access-2'}),
      );

      await Future.wait([api.get('/negocio'), api.get('/clientes'), api.get('/servicios')]);

      expect(backend.contar('POST /auth/refresh'), 1);
    });

    test('refresh rechazado (sesión cerrada en otro lado) → borra la sesión y avisa', () async {
      protegerConToken('GET /negocio', 'nunca', null);
      backend.cuando('POST /auth/refresh', (_) => Respuesta.error(401, 'SESION_INVALIDA'));

      await expectLater(api.get('/negocio'), throwsA(isA<NoAutenticado>()));

      expect(await tokens.leer(), isNull);
      expect(sesionesExpiradas, 1);
    });

    test('sin red al renovar → la sesión NO se borra: solo no se pudo comprobar', () async {
      // La petición llega y da 401; justo después se corta la red, así que
      // el refresh no sale.
      backend.cuando('GET /negocio', (_) {
        backend.sinRed = true;
        return Respuesta.error(401, 'TOKEN_EXPIRADO');
      });

      await expectLater(api.get('/negocio'), throwsA(isA<SinConexion>()));

      expect(await tokens.leer(), isNotNull);
      expect(sesionesExpiradas, 0);
    });

    test('un 401 de /auth/login no intenta renovar', () async {
      backend.cuando('POST /auth/login', (_) => Respuesta.error(401, 'ID_TOKEN_INVALIDO'));

      await expectLater(
        api.post('/auth/login', cuerpo: {'id_token': 'malo'}),
        throwsA(isA<NoAutenticado>().having((e) => e.codigo, 'codigo', 'ID_TOKEN_INVALIDO')),
      );
      expect(backend.contar('POST /auth/refresh'), 0);
    });
  });

  group('traducción de errores (Doc 5, Bloque 3)', () {
    test('422 → ErrorRechazado permanente, con código y detalles del catálogo', () async {
      backend.cuando(
        'PATCH /encargos/e1',
        (_) => Respuesta.error(422, 'DESCUENTO_INVALIDO', detalles: {'suma_trabajos': 20}),
      );

      await expectLater(
        api.patch('/encargos/e1', cuerpo: {'descuento': 25}),
        throwsA(
          isA<ErrorRechazado>()
              .having((e) => e.codigo, 'codigo', 'DESCUENTO_INVALIDO')
              .having((e) => e.detalles, 'detalles', {'suma_trabajos': 20})
              .having((e) => e.esPermanente, 'esPermanente', true),
        ),
      );
    });

    test('404 y 409 también son permanentes', () async {
      backend.cuando('GET /clientes/x', (_) => Respuesta.error(404, 'NO_ENCONTRADO'));
      backend.cuando('POST /clientes', (_) => Respuesta.error(409, 'CONFLICTO'));

      await expectLater(
        api.get('/clientes/x'),
        throwsA(predicate<ErrorApi>((e) => e.esPermanente)),
      );
      await expectLater(api.post('/clientes'), throwsA(predicate<ErrorApi>((e) => e.esPermanente)));
    });

    test('410 → SyncDemasiadoAntiguo', () async {
      backend.cuando('GET /sync', (_) => Respuesta.error(410, 'SYNC_DEMASIADO_ANTIGUO'));

      await expectLater(api.get('/sync'), throwsA(isA<SyncDemasiadoAntiguo>()));
    });

    test('429 → LimiteExcedido transitorio, con el Retry-After', () async {
      backend.cuando(
        'GET /sync',
        (_) => const Respuesta(429, null, {
          'retry-after': ['60'],
        }),
      );

      await expectLater(
        api.get('/sync'),
        throwsA(
          isA<LimiteExcedido>()
              .having((e) => e.reintentarEn, 'reintentarEn', const Duration(seconds: 60))
              .having((e) => e.esTransitorio, 'esTransitorio', true),
        ),
      );
    });

    test('5xx → transitorio', () async {
      backend.cuando('GET /sync', (_) => Respuesta.error(500, 'ERROR_INTERNO'));

      await expectLater(api.get('/sync'), throwsA(predicate<ErrorApi>((e) => e.esTransitorio)));
    });

    test('sin red → SinConexion transitorio', () async {
      backend.sinRed = true;

      await expectLater(
        api.get('/sync'),
        throwsA(isA<SinConexion>().having((e) => e.esTransitorio, 'esTransitorio', true)),
      );
    });

    test('los parámetros nulos no viajan en la query', () async {
      backend.cuando('GET /encargos', (_) => const Respuesta(200, {'datos': []}));

      await api.get('/encargos', query: {'estado': null, 'pagina': 2});

      expect(backend.peticiones.single.query, {'pagina': 2});
    });
  });
}
