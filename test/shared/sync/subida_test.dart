import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/infrastructure/http/error_api.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';
import 'package:gestor_encargos/shared/sync/subida.dart';

import '../../helpers/adaptador_falso.dart';

OperacionNueva operacion(
  String metodo,
  String ruta,
  String entidadId, {
  Map<String, Object?>? cuerpo,
}) => OperacionNueva(
  tipo: 'prueba',
  metodo: metodo,
  ruta: ruta,
  cuerpo: cuerpo,
  entidadId: entidadId,
  encargoId: 'e1',
);

void main() {
  late AdaptadorFalso backend;
  late BaseDatos base;
  late Outbox outbox;
  late Subida subida;

  setUp(() {
    backend = AdaptadorFalso();
    base = BaseDatos(NativeDatabase.memory());
    outbox = Outbox(base);
    subida = Subida(api: clienteApiDePrueba(backend), outbox: outbox);
  });
  tearDown(() async {
    await outbox.cerrar();
    await base.close();
  });

  List<String> enviadas() => [for (final p in backend.peticiones) '${p.metodo} ${p.ruta}'];

  test('sube en el orden en que se hicieron, con el método y cuerpo guardados', () async {
    backend.cuando('POST /encargos', (_) => const Respuesta(201, {}));
    backend.cuando('POST /encargos/e1/pagos', (_) => const Respuesta(201, {}));
    backend.cuando('PATCH /encargos/e1', (_) => const Respuesta(200, {}));
    backend.cuando('DELETE /encargos/e1/pagos/p1', (_) => const Respuesta(204));
    await outbox.encolar(operacion('POST', '/encargos', 'e1', cuerpo: {'id': 'e1'}));
    await outbox.encolar(operacion('POST', '/encargos/e1/pagos', 'p1', cuerpo: {'id': 'p1'}));
    await outbox.encolar(operacion('PATCH', '/encargos/e1', 'e1', cuerpo: {'descuento': 5}));
    await outbox.encolar(operacion('DELETE', '/encargos/e1/pagos/p1', 'p1'));

    expect(await subida.subir(), 4);

    expect(enviadas(), [
      'POST /encargos',
      'POST /encargos/e1/pagos',
      'PATCH /encargos/e1',
      'DELETE /encargos/e1/pagos/p1',
    ]);
    expect(backend.peticiones[2].cuerpo, {'descuento': 5});
    expect(await outbox.siguiente(), isNull);
  });

  test('un rechazo permanente se aparta y la cola sigue (decisión del usuario)', () async {
    backend.cuando('PATCH /encargos/e1', (_) => Respuesta.error(422, 'DESCUENTO_INVALIDO'));
    backend.cuando('POST /encargos/e1/notas', (_) => const Respuesta(201, {}));
    await outbox.encolar(operacion('PATCH', '/encargos/e1', 'e1', cuerpo: {'descuento': 999}));
    await outbox.encolar(operacion('POST', '/encargos/e1/notas', 'n1', cuerpo: {'id': 'n1'}));

    expect(await subida.subir(), 1);

    final apartadas = await outbox.apartadas().first;
    expect(apartadas.single.codigo, 'DESCUENTO_INVALIDO');
    expect(backend.contar('POST /encargos/e1/notas'), 1);
  });

  test('un DELETE con 404 sale como hecho: lo que se quería ya es cierto', () async {
    backend.cuando('DELETE /encargos/e1/trabajos/t1', (_) => Respuesta.error(404, 'NO_ENCONTRADO'));
    backend.cuando('PATCH /encargos/e1/trabajos/t2', (_) => Respuesta.error(404, 'NO_ENCONTRADO'));
    await outbox.encolar(operacion('DELETE', '/encargos/e1/trabajos/t1', 't1'));
    await outbox.encolar(
      operacion('PATCH', '/encargos/e1/trabajos/t2', 't2', cuerpo: {'precio': 1}),
    );

    expect(await subida.subir(), 1);

    expect([for (final op in await outbox.apartadas().first) op.entidadId], ['t2']);
  });

  test('un error transitorio detiene la subida en esa operación, sin saltarla', () async {
    backend.cuando('POST /encargos/e1/pagos', (_) => Respuesta.error(503, 'NO_DISPONIBLE'));
    await outbox.encolar(operacion('POST', '/encargos/e1/pagos', 'p1', cuerpo: {'id': 'p1'}));
    await outbox.encolar(operacion('POST', '/encargos/e1/notas', 'n1', cuerpo: {'id': 'n1'}));

    await expectLater(subida.subir(), throwsA(isA<ErrorServidor>()));

    expect(enviadas(), ['POST /encargos/e1/pagos'], reason: 'la nota no se adelanta');
    final cabeza = await outbox.siguiente();
    expect(cabeza!.entidadId, 'p1');
    expect(cabeza.intentos, 1);
  });

  test('al reintentar, sube desde donde quedó', () async {
    var caido = true;
    backend.cuando(
      'POST /encargos/e1/pagos',
      (_) => caido ? Respuesta.error(503, 'NO_DISPONIBLE') : const Respuesta(201, {}),
    );
    await outbox.encolar(operacion('POST', '/encargos/e1/pagos', 'p1', cuerpo: {'id': 'p1'}));
    await expectLater(subida.subir(), throwsA(isA<ErrorServidor>()));

    caido = false;

    expect(await subida.subir(), 1);
  });

  test('sesión terminada → se detiene sin apartar: la operación no tiene nada malo', () async {
    backend.cuando('POST /encargos/e1/pagos', (_) => Respuesta.error(401, 'TOKEN_EXPIRADO'));
    backend.cuando('POST /auth/refresh', (_) => Respuesta.error(401, 'SESION_INVALIDA'));
    await outbox.encolar(operacion('POST', '/encargos/e1/pagos', 'p1', cuerpo: {'id': 'p1'}));

    await expectLater(subida.subir(), throwsA(isA<NoAutenticado>()));

    expect(await outbox.apartadas().first, isEmpty);
    expect(await outbox.siguiente(), isNotNull);
  });

  test('un alta repetida (200 con el recurso existente) cuenta como subida', () async {
    backend.cuando('POST /clientes', (_) => const Respuesta(200, {'id': 'c1'}));
    await outbox.encolar(operacion('POST', '/clientes', 'c1', cuerpo: {'id': 'c1'}));

    expect(await subida.subir(), 1);
  });

  test('aplica el preparador antes de enviar', () async {
    backend.cuando('POST /encargos', (_) => const Respuesta(201, {}));
    await outbox.encolar(operacion('POST', '/encargos', 'e1', cuerpo: {'id': 'e1'}));
    final preparada = Subida(
      api: clienteApiDePrueba(backend),
      outbox: outbox,
      preparar: (op) async => op.copyWith(cuerpo: const Value('{"id":"e1","numero":101}')),
    );

    await preparada.subir();

    expect(backend.peticiones.single.cuerpo, {'id': 'e1', 'numero': 101});
  });

  test('dos llamadas a la vez no envían dos veces la misma operación', () async {
    backend.cuando('POST /clientes', (_) => const Respuesta(201, {}));
    await outbox.encolar(operacion('POST', '/clientes', 'c1', cuerpo: {'id': 'c1'}));

    await Future.wait([subida.subir(), subida.subir()]);

    expect(backend.contar('POST /clientes'), 1);
  });
}
