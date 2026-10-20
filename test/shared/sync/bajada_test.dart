import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';
import 'package:gestor_encargos/shared/infrastructure/auth/almacen_tokens.dart';
import 'package:gestor_encargos/shared/infrastructure/config/ambiente.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/infrastructure/http/cliente_api.dart';
import 'package:gestor_encargos/shared/infrastructure/http/error_api.dart';
import 'package:gestor_encargos/shared/sync/bajada.dart';

import '../../helpers/adaptador_falso.dart';

// Marcas como las emite el backend (`toISOString`).
const t1 = '2026-10-20T10:00:00.000Z';
const t2 = '2026-10-20T11:00:00.000Z';
const t3 = '2026-10-20T12:00:00.000Z';

Map<String, Object?> cliente(String id, {String nombre = 'Ana', String act = t1}) => {
  'id': id,
  'nombre': nombre,
  'telefono': '+51987654321',
  'creado_en': t1,
  'actualizado_en': act,
};

Map<String, Object?> encargo(String id, {String clienteId = 'c1'}) => {
  'id': id,
  'cliente_id': clienteId,
  'numero': 101,
  'descripcion': 'Basta de pantalón',
  'estado': 'RECIBIDO',
  'precio_total': 35.5,
  'descuento': 0,
  'saldo_pendiente': 15.5,
  'ubicacion_fisica': null,
  'notas_generales': null,
  'fecha_entrega_prometida': '2026-10-25',
  'fecha_entrega_acordada': '2026-10-25',
  'fecha_listo': null,
  'fecha_entrega_real': null,
  'creado_en': t1,
  'actualizado_en': t1,
};

Map<String, Object?> trabajo(String id, {String encargoId = 'e1', String? eliminado}) => {
  'id': id,
  'encargo_id': encargoId,
  'servicio_id': null,
  'objeto_recibido_id': null,
  'descripcion': 'Basta',
  'precio': 20,
  'creado_en': t1,
  'actualizado_en': eliminado ?? t1,
  'eliminado_en': eliminado,
};

Map<String, Object?> pago(String id) => {
  'id': id,
  'encargo_id': 'e1',
  'monto': 20,
  'origen_id': 1,
  'tipo': 'ADELANTO',
  'fecha': '2026-10-20',
  'creado_en': t1,
  'actualizado_en': t1,
  'eliminado_en': null,
};

/// Respuesta de `GET /sync` con las 9 colecciones siempre presentes, como el
/// backend real.
Respuesta pagina(
  String servidorTimestamp, {
  bool hasMore = false,
  List<Map<String, Object?>> clientes = const [],
  List<Map<String, Object?>> encargos = const [],
  List<Map<String, Object?>> trabajos = const [],
  List<Map<String, Object?>> pagos = const [],
  List<Map<String, Object?>> fotos = const [],
  List<Map<String, Object?>> materiales = const [],
}) => Respuesta(200, {
  'servidor_timestamp': servidorTimestamp,
  'has_more': hasMore,
  'cambios': {
    'clientes': clientes,
    'servicios': <Object>[],
    'encargos': encargos,
    'objetos_recibidos': <Object>[],
    'trabajos': trabajos,
    'materiales': materiales,
    'pagos': pagos,
    'notas': <Object>[],
    'fotos': fotos,
  },
});

void main() {
  late AdaptadorFalso backend;
  late BaseDatos base;
  late Set<String> protegidos;
  late Bajada bajada;

  setUp(() {
    backend = AdaptadorFalso();
    base = BaseDatos(NativeDatabase.memory());
    protegidos = {};
    bajada = Bajada(
      api: ClienteApi(
        ambiente: const Ambiente(apiUrl: 'http://api.test/api/v1'),
        tokens: AlmacenTokensEnMemoria(const Tokens(access: 'a', refresh: 'r')),
        adaptador: backend,
      ),
      base: base,
      idsProtegidos: () async => protegidos,
    );
  });
  tearDown(() => base.close());

  /// Responde `GET /sync` según el `since` recibido (`null` = sin since).
  void sync(Map<String?, Respuesta Function()> porSince) {
    backend.cuando('GET /sync', (p) {
      final since = p.query['since'] as String?;
      final respuesta = porSince[since];
      if (respuesta == null) fail('GET /sync con since inesperado: $since');
      return respuesta();
    });
  }

  Future<String?> since() => base.leerMetadato(Bajada.claveSince);

  group('primera sincronización', () {
    test('va sin since, guarda las filas y el servidor_timestamp como próximo since', () async {
      sync({
        null: () => pagina(t2, clientes: [cliente('c1')], encargos: [encargo('e1')]),
      });

      final resultado = await bajada.bajar();

      expect(backend.peticiones.single.query, isEmpty, reason: 'sin since = estado completo');
      expect(resultado.paginas, 1);
      expect(await since(), t2);
      expect((await base.select(base.clientes).getSingle()).telefono, '+51987654321');
    });

    test('dinero en céntimos y fechas de hecho como AAAA-MM-DD', () async {
      sync({
        null: () => pagina(t2, encargos: [encargo('e1')]),
      });

      await bajada.bajar();

      final fila = await base.select(base.encargos).getSingle();
      expect(fila.precioTotal, 3550);
      expect(fila.saldoPendiente, 1550);
      expect(fila.fechaEntregaPrometida, '2026-10-25');
      expect(fila.numero, 101);
    });

    test(
      'un hijo cuyo padre aún no llegó se guarda igual (las páginas no van por agregado)',
      () async {
        sync({
          null: () => pagina(t2, trabajos: [trabajo('t1', encargoId: 'llega-despues')]),
        });

        await bajada.bajar();

        expect(await base.select(base.trabajos).get(), hasLength(1));
      },
    );

    test('fotos: guarda la URL firmada; la clave interna de R2 nunca llega', () async {
      sync({
        null: () => pagina(
          t2,
          fotos: [
            {
              'id': 'f1',
              'encargo_id': 'e1',
              'objeto_recibido_id': null,
              'url_descarga': 'https://r2.test/f1?firma=x',
              'url_descarga_expira_en': '2026-10-27T10:00:00.000Z',
              'creado_en': t1,
              'actualizado_en': t1,
              'eliminado_en': null,
            },
          ],
        ),
      });

      await bajada.bajar();

      expect((await base.select(base.fotos).getSingle()).urlDescarga, 'https://r2.test/f1?firma=x');
    });
  });

  group('sincronizaciones siguientes', () {
    test('mandan el since guardado', () async {
      await base.guardarMetadato(Bajada.claveSince, t1);
      sync({t1: () => pagina(t2)});

      await bajada.bajar();

      expect(backend.peticiones.single.query, {'since': t1});
      expect(await since(), t2);
    });

    test('una fila repetida (solape de 10 s) no duplica ni cambia nada', () async {
      sync({
        null: () => pagina(t1, clientes: [cliente('c1')]),
      });
      await bajada.bajar();
      sync({
        t1: () => pagina(t2, clientes: [cliente('c1')]),
      });

      await bajada.bajar();

      expect(await base.select(base.clientes).get(), hasLength(1));
    });

    test('una versión más nueva actualiza la fila', () async {
      sync({
        null: () => pagina(t1, clientes: [cliente('c1')]),
      });
      await bajada.bajar();
      sync({
        t1: () => pagina(
          t3,
          clientes: [cliente('c1', nombre: 'Ana María', act: t2)],
        ),
      });

      await bajada.bajar();

      expect((await base.select(base.clientes).getSingle()).nombre, 'Ana María');
    });

    test('una versión más vieja NO pisa a una más nueva', () async {
      sync({
        null: () => pagina(
          t2,
          clientes: [cliente('c1', nombre: 'Nueva', act: t2)],
        ),
      });
      await bajada.bajar();
      sync({
        t2: () => pagina(
          t3,
          clientes: [cliente('c1', nombre: 'Vieja', act: t1)],
        ),
      });

      await bajada.bajar();

      expect((await base.select(base.clientes).getSingle()).nombre, 'Nueva');
    });

    test('un tombstone borra la fila local; uno de algo que nunca llegó no falla', () async {
      sync({
        null: () => pagina(t1, trabajos: [trabajo('t1')]),
      });
      await bajada.bajar();
      sync({
        t1: () => pagina(
          t2,
          trabajos: [
            trabajo('t1', eliminado: t2),
            trabajo('nunca', eliminado: t2),
          ],
        ),
      });

      await bajada.bajar();

      expect(await base.select(base.trabajos).get(), isEmpty);
    });
  });

  group('paginación (has_more)', () {
    test('pide páginas con la marca de cada una hasta que has_more es false', () async {
      sync({
        null: () => pagina(t1, hasMore: true, clientes: [cliente('c1')]),
        t1: () => pagina(t2, hasMore: true, clientes: [cliente('c2')]),
        t2: () => pagina(t3, clientes: [cliente('c3')]),
      });

      final resultado = await bajada.bajar();

      expect(resultado.paginas, 3);
      expect(await base.select(base.clientes).get(), hasLength(3));
      expect(await since(), t3);
    });

    test('si se corta a mitad, lo aplicado queda y la próxima sigue desde ahí', () async {
      backend.cuando('GET /sync', (_) {
        // Llega la página 1 y justo después se corta la red: la 2 no sale.
        backend.sinRed = true;
        return pagina(t1, hasMore: true, clientes: [cliente('c1')]);
      });

      await expectLater(bajada.bajar(), throwsA(isA<SinConexion>()));

      expect(await base.select(base.clientes).get(), hasLength(1));
      expect(await since(), t1);
    });

    test('has_more sin avanzar la marca → error, no un bucle infinito', () async {
      await base.guardarMetadato(Bajada.claveSince, t1);
      sync({t1: () => pagina(t1, hasMore: true)});

      await expectLater(bajada.bajar(), throwsStateError);
    });
  });

  group('atomicidad por página', () {
    test('una fila inválida descarta la página entera y la marca no avanza', () async {
      final encargoMalo = encargo('e1')..['precio_total'] = 1.234; // tercer decimal
      sync({
        null: () => pagina(t2, clientes: [cliente('c1')], encargos: [encargoMalo]),
      });

      await expectLater(bajada.bajar(), throwsA(isA<ValorInvalido>()));

      expect(await base.select(base.clientes).get(), isEmpty);
      expect(await since(), isNull);
    });
  });

  group('filas con cambios pendientes en la Outbox', () {
    test('ni se actualizan ni se borran: lo local pendiente gana', () async {
      sync({
        null: () => pagina(
          t1,
          clientes: [cliente('c1', nombre: 'Local')],
          trabajos: [trabajo('t1')],
        ),
      });
      await bajada.bajar();
      protegidos = {'c1', 't1'};
      sync({
        t1: () => pagina(
          t2,
          clientes: [cliente('c1', nombre: 'Servidor', act: t2)],
          trabajos: [trabajo('t1', eliminado: t2)],
        ),
      });

      await bajada.bajar();

      expect((await base.select(base.clientes).getSingle()).nombre, 'Local');
      expect(await base.select(base.trabajos).get(), hasLength(1));
      expect(await since(), t2, reason: 'la marca avanza igual');
    });
  });

  group('410 — el dispositivo quedó atrás de la purga', () {
    test('descarta lo sincronizado, conserva lo pendiente y rehace todo sin since', () async {
      sync({
        null: () => pagina(t1, clientes: [cliente('c1'), cliente('pendiente')]),
      });
      await bajada.bajar();
      await base.guardarMetadato('sesion.negocio_id', 'n1');
      protegidos = {'pendiente'};
      sync({
        t1: () => Respuesta.error(410, 'SYNC_DEMASIADO_ANTIGUO'),
        null: () => pagina(t3, clientes: [cliente('c9')]),
      });

      final resultado = await bajada.bajar();

      expect(resultado.resincronizo, isTrue);
      final ids = (await base.select(base.clientes).get()).map((c) => c.id);
      expect(ids, unorderedEquals(['pendiente', 'c9']), reason: 'c1 ya no existe en el servidor');
      expect(await since(), t3);
      expect(await base.leerMetadato('sesion.negocio_id'), 'n1', reason: 'solo datos de sync');
    });

    test('un segundo 410 seguido es un error, no un bucle', () async {
      await base.guardarMetadato(Bajada.claveSince, t1);
      backend.cuando('GET /sync', (_) => Respuesta.error(410, 'SYNC_DEMASIADO_ANTIGUO'));

      await expectLater(bajada.bajar(), throwsA(isA<SyncDemasiadoAntiguo>()));
      expect(backend.contar('GET /sync'), 2);
    });
  });

  test('dos llamadas a la vez comparten la misma bajada', () async {
    sync({
      null: () => pagina(t2, clientes: [cliente('c1')]),
    });

    await Future.wait([bajada.bajar(), bajada.bajar()]);

    expect(backend.contar('GET /sync'), 1);
  });

  test('aplicar avisa a los streams de Drift: la UI se refresca sola', () async {
    sync({
      null: () => pagina(t1, pagos: [pago('p1')]),
    });
    final emisiones = <int>[];
    final sub = base.select(base.pagos).watch().listen((filas) => emisiones.add(filas.length));
    await pumpEventQueue();

    await bajada.bajar();
    await pumpEventQueue();

    expect(emisiones.last, 1);
    await sub.cancel();
  });
}
