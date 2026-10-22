import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/infrastructure/auth/almacen_tokens.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/infrastructure/http/error_api.dart';
import 'package:gestor_encargos/shared/sync/bajada.dart';
import 'package:gestor_encargos/shared/sync/motor_sync.dart';
import 'package:gestor_encargos/shared/sync/numeracion.dart';
import 'package:gestor_encargos/shared/sync/origenes_pago.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';
import 'package:gestor_encargos/shared/sync/subida.dart';

import '../../helpers/adaptador_falso.dart';

const t1 = '2026-10-20T10:00:00.000Z';
const t2 = '2026-10-20T11:00:00.000Z';

Respuesta paginaVacia(String marca, {List<Map<String, Object?>> clientes = const []}) =>
    Respuesta(200, {
      'servidor_timestamp': marca,
      'has_more': false,
      'cambios': {
        for (final c in [
          'clientes',
          'servicios',
          'encargos',
          'objetos_recibidos',
          'trabajos',
          'materiales',
          'pagos',
          'notas',
          'fotos',
        ])
          c: c == 'clientes' ? clientes : <Object>[],
      },
    });

void main() {
  late AdaptadorFalso backend;
  late BaseDatos base;
  late Outbox outbox;
  late AlmacenTokensEnMemoria tokens;
  late List<int> esperasPedidas;
  late MotorSync motor;

  setUp(() {
    backend = AdaptadorFalso();
    base = BaseDatos(NativeDatabase.memory());
    outbox = Outbox(base);
    tokens = AlmacenTokensEnMemoria(const Tokens(access: 'a', refresh: 'r'));
    esperasPedidas = [];
    final api = clienteApiDePrueba(backend);
    final numeracion = Numeracion(base: base, api: api);
    motor = MotorSync(
      bajada: Bajada(api: api, base: base, idsProtegidos: outbox.idsProtegidos),
      subida: Subida(api: api, outbox: outbox, preparar: numeracion.numerarSiFalta),
      numeracion: numeracion,
      tokens: tokens,
      // Reintentos casi inmediatos: lo que se prueba es que ocurran y con qué
      // número de fallos, no cuánto se espera (eso es `esperaPorDefecto`).
      espera: (fallos) {
        esperasPedidas.add(fallos);
        return const Duration(milliseconds: 1);
      },
    );
    backend.cuando(
      'POST /encargos/reservar-bloque-numeros',
      (_) => const Respuesta(200, {'desde': 1, 'hasta': 100}),
    );
    backend.cuando('GET /sync', (_) => paginaVacia(t1));
  });
  tearDown(() async {
    motor.cerrar();
    await outbox.cerrar();
    await base.close();
  });

  /// Espera a que el motor no tenga vueltas en curso ni reintentos inmediatos.
  Future<void> hastaQue(bool Function() condicion) async {
    for (var i = 0; i < 200 && !condicion(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(condicion(), isTrue, reason: 'la condición no se cumplió a tiempo');
  }

  List<String> enviadas() => [for (final p in backend.peticiones) '${p.metodo} ${p.ruta}'];

  test('sin sesión no hace nada', () async {
    await tokens.borrar();

    await motor.sincronizar();

    expect(backend.peticiones, isEmpty);
  });

  test('una vuelta: reserva números, sube la Outbox y después baja', () async {
    backend.cuando('POST /clientes', (_) => const Respuesta(201, {}));
    await outbox.encolar(
      const OperacionNueva(
        tipo: 'crear_cliente',
        metodo: 'POST',
        ruta: '/clientes',
        cuerpo: {'id': 'c1'},
        entidadId: 'c1',
      ),
    );

    await motor.sincronizar();

    expect(enviadas(), ['POST /encargos/reservar-bloque-numeros', 'POST /clientes', 'GET /sync']);
    expect(motor.estado.ultimaCompleta, isNotNull);
    expect(motor.estado.ultimoError, isNull);
    expect(motor.estado.sincronizando, isFalse);
  });

  test('lo que se acaba de subir baja en la misma vuelta (ya no está protegido)', () async {
    await base
        .into(base.clientes)
        .insert(
          ClientesCompanion.insert(
            id: 'c1',
            creadoEn: t1,
            actualizadoEn: t1,
            nombre: 'Ana',
            nombreBusqueda: 'ana',
          ),
        );
    await outbox.encolar(
      const OperacionNueva(
        tipo: 'editar_cliente',
        metodo: 'PATCH',
        ruta: '/clientes/c1',
        cuerpo: {'nombre': 'Ana María'},
        entidadId: 'c1',
      ),
    );
    backend.cuando('PATCH /clientes/c1', (_) => const Respuesta(200, {}));
    backend.cuando(
      'GET /sync',
      (_) => paginaVacia(
        t2,
        clientes: [
          {
            'id': 'c1',
            'nombre': 'Ana María',
            'telefono': null,
            'creado_en': t1,
            'actualizado_en': t2,
          },
        ],
      ),
    );

    await motor.sincronizar();

    expect((await base.select(base.clientes).getSingle()).nombre, 'Ana María');
  });

  test('sin red: lo deja anotado y reintenta solo hasta que vuelve', () async {
    backend.sinRed = true;

    await motor.sincronizar();

    expect(motor.estado.sinConexion, isTrue);
    expect(motor.estado.proximoIntento, isNotNull);

    backend.sinRed = false;
    await hastaQue(() => motor.estado.ultimaCompleta != null);
    expect(motor.estado.ultimoError, isNull);
    expect(esperasPedidas.first, 1);
  });

  test('las esperas crecen con cada fallo seguido y se reinician al salir bien', () async {
    backend.sinRed = true;
    await motor.sincronizar();
    await hastaQue(() => esperasPedidas.length >= 3);

    expect(esperasPedidas.take(3), [1, 2, 3]);

    backend.sinRed = false;
    await hastaQue(() => motor.estado.ultimoError == null);
    backend.sinRed = true;
    final antes = esperasPedidas.length;
    await motor.sincronizar();

    expect(esperasPedidas[antes], 1, reason: 'contador reiniciado');
  });

  test('un 429 respeta el Retry-After del servidor si es mayor', () async {
    final motorReal = MotorSync(
      bajada: Bajada(api: clienteApiDePrueba(backend), base: base),
      subida: Subida(api: clienteApiDePrueba(backend), outbox: outbox),
      numeracion: Numeracion(base: base, api: clienteApiDePrueba(backend)),
      tokens: tokens,
      reloj: () => DateTime.utc(2026, 10, 20, 10),
    );
    addTearDown(motorReal.cerrar);
    backend.cuando(
      'GET /sync',
      (_) => const Respuesta(429, null, {
        'retry-after': ['120'],
      }),
    );

    await motorReal.sincronizar();

    expect(motorReal.estado.ultimoError, isA<LimiteExcedido>());
    expect(motorReal.estado.proximoIntento, DateTime.utc(2026, 10, 20, 10, 2));
  });

  test('sesión terminada: no reintenta (el login dispara una vuelta nueva)', () async {
    backend.cuando('GET /sync', (_) => Respuesta.error(401, 'TOKEN_EXPIRADO'));
    backend.cuando('POST /auth/refresh', (_) => Respuesta.error(401, 'SESION_INVALIDA'));

    await motor.sincronizar();

    expect(motor.estado.ultimoError, isA<NoAutenticado>());
    expect(motor.estado.proximoIntento, isNull);
    expect(esperasPedidas, isEmpty);
  });

  test('un rechazo permanente al reservar números no frena la vuelta', () async {
    backend.cuando(
      'POST /encargos/reservar-bloque-numeros',
      (_) => Respuesta.error(400, 'SOLICITUD_INVALIDA'),
    );

    await motor.sincronizar();

    expect(enviadas(), contains('GET /sync'));
    expect(motor.estado.ultimoError, isNull);
  });

  test('pedidos durante una vuelta → una vuelta más al terminar, nunca dos a la vez', () async {
    var simultaneas = 0;
    var maximo = 0;
    final liberar = Completer<void>();
    final bajadaLenta = _BajadaLenta(liberar.future, () {
      simultaneas++;
      maximo = simultaneas > maximo ? simultaneas : maximo;
    }, () => simultaneas--);
    final lenta = MotorSync(
      bajada: bajadaLenta,
      subida: Subida(api: clienteApiDePrueba(backend), outbox: outbox),
      numeracion: Numeracion(base: base, api: clienteApiDePrueba(backend)),
      tokens: tokens,
    );
    addTearDown(lenta.cerrar);

    final primera = lenta.sincronizar();
    await pumpEventQueue();
    unawaited(lenta.sincronizar());
    unawaited(lenta.sincronizar());
    liberar.complete();
    await primera;

    expect(bajadaLenta.vueltas, 2, reason: 'tres pedidos = la vuelta en curso + una');
    expect(maximo, 1);
  });

  test('esperaPorDefecto: 5 s, 10 s, 20 s… con tope de 5 min', () {
    expect(
      [
        for (final f in [1, 2, 3, 4, 5, 6, 7, 20]) esperaPorDefecto(f).inSeconds,
      ],
      [5, 10, 20, 40, 80, 160, 300, 300],
    );
  });
  group('orígenes de pago (Doc 7 v1.3)', () {
    late MotorSync conOrigenes;

    setUp(() {
      final api = clienteApiDePrueba(backend);
      final numeracion = Numeracion(base: base, api: api);
      conOrigenes = MotorSync(
        bajada: Bajada(api: api, base: base, idsProtegidos: outbox.idsProtegidos),
        subida: Subida(api: api, outbox: outbox, preparar: numeracion.numerarSiFalta),
        numeracion: numeracion,
        tokens: tokens,
        origenes: OrigenesPagoRemotos(base: base, api: api),
        espera: (_) => const Duration(hours: 1),
      );
    });
    tearDown(() => conOrigenes.cerrar());

    test('se bajan después de /sync, una sola vez por arranque', () async {
      backend.cuando(
        'GET /origenes-pago',
        (_) => const Respuesta(200, [
          {'id': 1, 'nombre': 'Efectivo', 'activo': true},
        ]),
      );

      await conOrigenes.sincronizar();
      await conOrigenes.sincronizar();

      expect(enviadas().where((e) => !e.startsWith('POST')), [
        'GET /sync',
        'GET /origenes-pago',
        'GET /sync',
      ]);
      expect(await base.select(base.origenesPago).get(), hasLength(1));
    });

    test('si fallan, la vuelta igual cuenta como completa', () async {
      backend.cuando('GET /origenes-pago', (_) => Respuesta.error(404, 'NO_ENCONTRADO'));

      await conOrigenes.sincronizar();

      expect(conOrigenes.estado.ultimoError, isNull);
      expect(conOrigenes.estado.ultimaCompleta, isNotNull);
      expect(conOrigenes.estado.proximoIntento, isNull);
    });
  });
}

/// Bajada que espera una señal para terminar, para observar qué pasa con los
/// pedidos que llegan mientras una vuelta está en curso.
class _BajadaLenta implements Bajada {
  _BajadaLenta(this.liberar, this.alEmpezar, this.alTerminar);

  final Future<void> liberar;
  final void Function() alEmpezar;
  final void Function() alTerminar;
  int vueltas = 0;

  @override
  Future<ResultadoBajada> bajar() async {
    vueltas++;
    alEmpezar();
    await liberar;
    alTerminar();
    return const ResultadoBajada(paginas: 1, resincronizo: false);
  }
}
