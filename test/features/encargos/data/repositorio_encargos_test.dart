import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/encargos/data/repositorio_encargos.dart';
import 'package:gestor_encargos/features/encargos/domain/encargo.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/sync/numeracion.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/adaptador_falso.dart';
import '../../../helpers/encargos_prueba.dart';

void main() {
  late BaseDatos base;
  late Outbox outbox;
  late Numeracion numeracion;
  late RepositorioEncargos repositorio;

  setUp(() {
    base = BaseDatos(NativeDatabase.memory());
    outbox = Outbox(base);
    numeracion = Numeracion(base: base, api: clienteApiDePrueba(AdaptadorFalso()));
    repositorio = RepositorioEncargos(
      base: base,
      outbox: outbox,
      numeracion: numeracion,
      nuevoId: () => 'e1',
      reloj: () => DateTime.utc(2026, 10, 22, 15),
    );
  });
  tearDown(() async {
    await outbox.cerrar();
    await base.close();
  });

  Future<List<OperacionOutbox>> cola() => base.select(base.operacionesOutbox).get();
  Future<void> conBloque(int desde, int hasta) =>
      base.guardarMetadato(Numeracion.claveRangos, '[[$desde,$hasta]]');

  Future<void> crear({String descripcion = ' Basta de pantalón ', DateTime? fecha}) =>
      repositorio.crear(
        clienteId: 'ana',
        descripcion: descripcion,
        fechaEntregaAcordada: fecha ?? DateTime.utc(2026, 10, 24),
      );

  test('nace como en el backend: INGRESADO, en cero y prometida = acordada', () async {
    await conBloque(15, 100);
    await crear();

    final fila = await base.select(base.encargos).getSingle();
    expect(
      [fila.clienteId, fila.numero, fila.descripcion, fila.estado],
      ['ana', 15, 'Basta de pantalón', 'INGRESADO'],
    );
    expect([fila.precioTotal, fila.descuento, fila.saldoPendiente], [0, 0, 0]);
    expect([fila.fechaEntregaAcordada, fila.fechaEntregaPrometida], ['2026-10-24', '2026-10-24']);
    expect(fila.creadoEn, '2026-10-22T15:00:00.000Z');
    expect(fila.actualizadoEn, sinVersionDelServidor);
  });

  test('el POST lleva el número del bloque y no envía la fecha prometida', () async {
    await conBloque(15, 100);
    await crear();

    final op = (await cola()).single;
    expect(
      [op.tipo, op.metodo, op.ruta, op.entidadId, op.encargoId],
      [TiposOperacion.crearEncargo, 'POST', '/encargos', 'e1', 'e1'],
    );
    expect(op.cuerpoJson, {
      'id': 'e1',
      'cliente_id': 'ana',
      'numero': 15,
      'descripcion': 'Basta de pantalón',
      'fecha_entrega_acordada': '2026-10-24',
    });
    expect(await numeracion.restantes(), 85, reason: 'el 15 ya se gastó');
  });

  test('sin bloque (agotado sin conexión) se crea igual, sin número: se numera al subir', () async {
    await crear();

    expect((await base.select(base.encargos).getSingle()).numero, isNull);
    expect((await cola()).single.cuerpoJson!.containsKey('numero'), isFalse);
  });

  test('una fecha pasada se acepta (decisión del usuario)', () async {
    await crear(fecha: DateTime.utc(2026, 9, 1));

    expect((await base.select(base.encargos).getSingle()).fechaEntregaAcordada, '2026-09-01');
  });

  test('descripción vacía no escribe nada ni gasta número', () async {
    await conBloque(15, 100);

    await expectLater(crear(descripcion: '  '), throwsA(isA<ValorInvalido>()));

    expect(await base.select(base.encargos).get(), isEmpty);
    expect(await cola(), isEmpty);
    expect(await numeracion.restantes(), 86);
  });

  group('observar (detalle)', () {
    Future<void> conAna() => base
        .into(base.clientes)
        .insert(
          ClientesCompanion.insert(
            id: 'ana',
            creadoEn: '2026-10-01T15:00:00.000Z',
            actualizadoEn: '2026-10-01T15:00:00.000Z',
            nombre: 'Ana Pérez',
            nombreBusqueda: 'ana perez',
            telefono: const Value('+51987654321'),
          ),
        );

    test('trae los datos generales con su cliente', () async {
      await conAna();
      await insertarEncargo(
        base,
        id: 'e1',
        clienteId: 'ana',
        numero: 47,
        creadoEn: '2026-10-01T15:00:00.000Z',
        estado: 'EN_PROCESO',
        precioCentimos: 30000,
        saldoCentimos: 10000,
        descuentoCentimos: 500,
        entregaPrometida: '2026-10-20',
        entregaAcordada: '2026-10-24',
        ubicacion: 'Cajón 3',
        notas: 'Llamar antes',
      );

      final e = (await repositorio.observar('e1').first)!;

      expect(
        [e.numero, e.cliente!.nombre, e.cliente!.telefono!.valor],
        [47, 'Ana Pérez', '+51987654321'],
      );
      expect(
        [e.precioTotal, e.saldoPendiente, e.descuento],
        [Monto.desdeCentimos(30000), Monto.desdeCentimos(10000), Monto.desdeCentimos(500)],
      );
      expect(
        [e.fechaEntregaPrometida, e.fechaEntregaAcordada],
        [DateTime.utc(2026, 10, 20), DateTime.utc(2026, 10, 24)],
      );
      expect([e.ubicacionFisica, e.notasGenerales], ['Cajón 3', 'Llamar antes']);
    });

    test('inexistente: null', () async {
      expect(await repositorio.observar('nada').first, isNull);
    });

    test('es reactivo: lo recién creado aparece sin volver a abrir', () async {
      await conAna();
      final vistos = <int?>[];
      final sub = repositorio.observar('e1').listen((e) => vistos.add(e?.numero));
      await pumpEventQueue();

      await conBloque(15, 100);
      await crear();
      await pumpEventQueue();

      expect(vistos, [null, 15]);
      await sub.cancel();
    });
  });

  group('editar (S2c)', () {
    Future<Encargo> conEncargo({String estado = 'EN_PROCESO'}) async {
      await insertarEncargo(
        base,
        id: 'e1',
        clienteId: 'ana',
        creadoEn: '2026-10-01T15:00:00.000Z',
        estado: estado,
        descripcion: 'Vestido',
        entregaAcordada: '2026-10-24',
        ubicacion: 'Cajón 3',
      );
      return (await repositorio.observar('e1').first)!;
    }

    Future<void> editar(
      Encargo actual, {
      String? descripcion,
      DateTime? fecha,
      String? ubicacion,
      String? notas,
    }) => repositorio.editar(
      actual,
      descripcion: descripcion ?? actual.descripcion,
      fechaEntregaAcordada: fecha ?? actual.fechaEntregaAcordada,
      ubicacion: ubicacion ?? actual.ubicacionFisica ?? '',
      notas: notas ?? actual.notasGenerales ?? '',
    );

    test('PATCH solo con lo que cambió; la fila local cambia en la misma transacción', () async {
      final actual = await conEncargo();

      await editar(actual, descripcion: ' Vestido de noche ', notas: 'Llamar antes');

      final op = (await cola()).single;
      expect(
        [op.tipo, op.metodo, op.ruta, op.encargoId],
        [TiposEncargo.editar, 'PATCH', '/encargos/e1', 'e1'],
      );
      expect(op.cuerpoJson, {'descripcion': 'Vestido de noche', 'notas_generales': 'Llamar antes'});
      final fila = await base.select(base.encargos).getSingle();
      expect(
        [fila.descripcion, fila.notasGenerales, fila.ubicacionFisica],
        ['Vestido de noche', 'Llamar antes', 'Cajón 3'],
      );
      expect(fila.actualizadoEn, '2026-10-01T15:00:00.000Z', reason: 'no adelanta la versión');
    });

    test('reprogramar mueve solo la acordada: la prometida queda', () async {
      final actual = await conEncargo();

      await editar(actual, fecha: DateTime.utc(2026, 10, 30));

      expect((await cola()).single.cuerpoJson, {'fecha_entrega_acordada': '2026-10-30'});
      final fila = await base.select(base.encargos).getSingle();
      expect([fila.fechaEntregaPrometida, fila.fechaEntregaAcordada], ['2026-10-24', '2026-10-30']);
    });

    test('ubicación vacía se borra con null explícito', () async {
      final actual = await conEncargo();

      await editar(actual, ubicacion: '  ');

      expect((await cola()).single.cuerpoJson, {'ubicacion_fisica': null});
      expect((await base.select(base.encargos).getSingle()).ubicacionFisica, isNull);
    });

    test('sin cambios no encola nada', () async {
      final actual = await conEncargo();

      expect(
        await repositorio.editar(
          actual,
          descripcion: ' Vestido ',
          fechaEntregaAcordada: actual.fechaEntregaAcordada,
          ubicacion: 'Cajón 3',
          notas: '',
        ),
        isFalse,
      );
      expect(await cola(), isEmpty);
    });

    test('descripción vacía no escribe nada', () async {
      final actual = await conEncargo();

      await expectLater(editar(actual, descripcion: ' '), throwsA(isA<ValorInvalido>()));
      expect(await cola(), isEmpty);
    });

    for (final estado in ['ENTREGADO', 'CANCELADO']) {
      test('$estado no se reprograma (decisión del usuario), pero lo demás sí', () async {
        final actual = await conEncargo(estado: estado);

        await expectLater(
          editar(actual, fecha: DateTime.utc(2026, 10, 30)),
          throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'ENCARGO_CERRADO')),
        );
        expect(await cola(), isEmpty);

        await editar(actual, notas: 'Recogió la hija');
        expect((await cola()).single.cuerpoJson, {'notas_generales': 'Recogió la hija'});
      });
    }
  });

  group('descuento (S3b2)', () {
    Future<Encargo> conTrabajos(List<int> centimos, {String estado = 'EN_PROCESO'}) async {
      await insertarEncargo(
        base,
        id: 'e1',
        clienteId: 'ana',
        creadoEn: '2026-10-01T15:00:00.000Z',
        estado: estado,
        precioCentimos: centimos.fold<int>(0, (a, b) => a + b),
        saldoCentimos: centimos.fold<int>(0, (a, b) => a + b),
      );
      for (final (i, precio) in centimos.indexed) {
        await base
            .into(base.trabajos)
            .insert(
              TrabajosCompanion.insert(
                id: 't$i',
                creadoEn: '2026-10-01T15:00:00.000Z',
                actualizadoEn: '2026-10-01T15:00:00.000Z',
                encargoId: 'e1',
                descripcion: 'Trabajo $i',
                precio: precio,
              ),
            );
      }
      return (await repositorio.observar('e1').first)!;
    }

    Future<bool> conDescuento(Encargo actual, Monto descuento) => repositorio.editar(
      actual,
      descripcion: actual.descripcion,
      fechaEntregaAcordada: actual.fechaEntregaAcordada,
      ubicacion: actual.ubicacionFisica ?? '',
      notas: actual.notasGenerales ?? '',
      descuento: descuento,
    );

    test('PRD 2: suma S/33 y descuento S/3 → total S/30; viaja en el PATCH', () async {
      final actual = await conTrabajos([2000, 1300]);
      await insertarPago(base, id: 'p1', encargoId: 'e1', centimos: 1000);

      expect(await conDescuento(actual, Monto.desde(3)), isTrue);

      final fila = await base.select(base.encargos).getSingle();
      expect([fila.precioTotal, fila.descuento, fila.saldoPendiente], [3000, 300, 2000]);
      expect((await cola()).single.cuerpoJson, {'descuento': 3});
      expect(fila.actualizadoEn, '2026-10-01T15:00:00.000Z');
    });

    test('mayor que la suma (de Drift, no de la pantalla): no guarda nada', () async {
      final actual = await conTrabajos([2000]);

      await expectLater(
        conDescuento(actual, Monto.desde(25)),
        throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'DESCUENTO_INVALIDO')),
      );
      expect(await cola(), isEmpty);
      expect((await base.select(base.encargos).getSingle()).descuento, 0);
    });

    test('quitarlo (S/ 0) también viaja; el mismo valor no', () async {
      final actual = await conTrabajos([2000]);
      await conDescuento(actual, Monto.desde(5));
      final conCinco = (await repositorio.observar('e1').first)!;

      expect(await conDescuento(conCinco, Monto.desde(5)), isFalse);
      await conDescuento(conCinco, Monto.cero);

      expect(
        [for (final op in await cola()) op.cuerpoJson],
        [
          {'descuento': 5},
          {'descuento': 0},
        ],
      );
      expect((await base.select(base.encargos).getSingle()).precioTotal, 2000);
    });

    test('entregado: el descuento no cambia (decisión del usuario)', () async {
      final actual = await conTrabajos([2000], estado: 'ENTREGADO');

      await expectLater(
        conDescuento(actual, Monto.desde(1)),
        throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'ENCARGO_CERRADO')),
      );
      expect(await cola(), isEmpty);
    });
  });
}
