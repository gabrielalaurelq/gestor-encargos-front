import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/servicios/data/repositorio_servicios.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/sync/bajada.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/adaptador_falso.dart';

void main() {
  late BaseDatos base;
  late Outbox outbox;
  late RepositorioServicios repositorio;
  var ids = 0;

  setUp(() {
    base = BaseDatos(NativeDatabase.memory());
    outbox = Outbox(base);
    ids = 0;
    repositorio = RepositorioServicios(
      base: base,
      outbox: outbox,
      nuevoId: () => 's${++ids}',
      // Reloj del teléfono adelantado un año: no debe colarse en
      // `actualizado_en` (ver `sinVersionDelServidor`).
      reloj: () => DateTime.utc(2027, 10, 20),
    );
  });
  tearDown(() async {
    await outbox.cerrar();
    await base.close();
  });

  Future<List<OperacionOutbox>> cola() => base.select(base.operacionesOutbox).get();

  test('crear: la fila y su POST quedan juntos, con el id del teléfono', () async {
    final servicio = await repositorio.crear(
      nombre: ' Basta de jean ',
      precio: Monto.desdeCentimos(2050),
    );

    final fila = await base.select(base.servicios).getSingle();
    expect([fila.id, fila.nombre, fila.precio, fila.activo], ['s1', 'Basta de jean', 2050, true]);
    expect(fila.actualizadoEn, sinVersionDelServidor);
    final op = (await cola()).single;
    expect([op.metodo, op.ruta, op.entidadId], ['POST', '/servicios', servicio.id]);
    expect(op.cuerpoJson, {'id': 's1', 'nombre': 'Basta de jean', 'precio': 20.5});
  });

  test('crear con datos inválidos no escribe nada', () async {
    await expectLater(
      repositorio.crear(nombre: '  ', precio: Monto.cero),
      throwsA(isA<ValorInvalido>()),
    );

    expect(await base.select(base.servicios).get(), isEmpty);
    expect(await cola(), isEmpty);
  });

  test('cambiar precio: PATCH solo con el precio, sin adelantar actualizado_en', () async {
    await repositorio.crear(nombre: 'Basta', precio: Monto.desdeCentimos(2000));

    await repositorio.cambiarPrecio('s1', Monto.desdeCentimos(2200));

    final fila = await base.select(base.servicios).getSingle();
    expect(fila.precio, 2200);
    expect(fila.actualizadoEn, sinVersionDelServidor);
    final op = (await cola()).last;
    expect([op.metodo, op.ruta], ['PATCH', '/servicios/s1']);
    expect(op.cuerpoJson, {'precio': 22});
  });

  test('cambiar precio a negativo se rechaza antes de escribir', () async {
    await repositorio.crear(nombre: 'Basta', precio: Monto.desdeCentimos(2000));

    await expectLater(
      repositorio.cambiarPrecio('s1', Monto.desde('-1')),
      throwsA(isA<ValorInvalido>()),
    );

    expect((await cola()).length, 1, reason: 'solo el alta');
  });

  test('desactivar y reactivar: PATCH de activo', () async {
    await repositorio.crear(nombre: 'Basta', precio: Monto.cero);

    await repositorio.cambiarActivo('s1', activo: false);
    expect((await base.select(base.servicios).getSingle()).activo, isFalse);
    await repositorio.cambiarActivo('s1', activo: true);

    final cuerpos = [for (final op in (await cola()).skip(1)) op.cuerpoJson];
    expect(cuerpos, [
      {'activo': false},
      {'activo': true},
    ]);
  });

  test('editar un servicio que no existe falla sin encolar', () async {
    await expectLater(repositorio.cambiarActivo('nada', activo: false), throwsStateError);

    expect(await cola(), isEmpty);
  });

  test('observar: todos, activos y desactivados, por nombre sin distinguir mayúsculas', () async {
    final listas = repositorio.observar();
    await repositorio.crear(nombre: 'zurcido', precio: Monto.cero);
    await repositorio.crear(nombre: 'Basta', precio: Monto.cero);
    await repositorio.cambiarActivo('s1', activo: false);

    final lista = await listas.first;

    expect([for (final s in lista) (s.nombre, s.activo)], [('Basta', true), ('zurcido', false)]);
  });

  test('con el reloj del teléfono adelantado, la versión del servidor igual baja', () async {
    // El caso que motiva `sinVersionDelServidor`: alta local, sube, y el
    // servidor la devuelve con su propia hora, anterior a la del teléfono.
    await repositorio.crear(nombre: 'basta', precio: Monto.desdeCentimos(2000));
    for (final op in await cola()) {
      await outbox.completar(op.id);
    }
    final backend = AdaptadorFalso()
      ..cuando(
        'GET /sync',
        (_) => const Respuesta(200, {
          'servidor_timestamp': '2026-10-20T10:00:00.000Z',
          'has_more': false,
          'cambios': {
            'servicios': [
              {
                'id': 's1',
                'nombre': 'basta',
                'precio': 25,
                'activo': true,
                'creado_en': '2026-10-20T09:59:00.000Z',
                'actualizado_en': '2026-10-20T09:59:30.000Z',
              },
            ],
          },
        }),
      );

    await Bajada(
      api: clienteApiDePrueba(backend),
      base: base,
      idsProtegidos: outbox.idsProtegidos,
    ).bajar();

    final fila = await base.select(base.servicios).getSingle();
    expect(fila.precio, 2500, reason: 'otro dispositivo le cambió el precio');
    expect(fila.actualizadoEn, '2026-10-20T09:59:30.000Z');
  });
}
