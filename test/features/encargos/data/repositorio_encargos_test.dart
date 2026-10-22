import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/encargos/data/repositorio_encargos.dart';
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
}
