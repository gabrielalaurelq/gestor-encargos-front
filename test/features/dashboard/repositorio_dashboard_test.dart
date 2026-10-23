import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/dashboard/data/repositorio_dashboard.dart';
import 'package:gestor_encargos/features/dashboard/domain/dashboard.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';

import '../../helpers/encargos_prueba.dart';

const marca = '2026-10-01T15:00:00.000Z';

void main() {
  late BaseDatos base;
  late RepositorioDashboard dashboard;
  final hoy = DateTime.utc(2026, 10, 23);

  setUp(() async {
    base = BaseDatos(NativeDatabase.memory());
    dashboard = RepositorioDashboard(base: base);
    await base
        .into(base.clientes)
        .insert(
          ClientesCompanion.insert(
            id: 'ana',
            creadoEn: marca,
            actualizadoEn: marca,
            nombre: 'Ana García',
            nombreBusqueda: 'ana garcia',
          ),
        );
  });
  tearDown(() => base.close());

  var siguiente = 0;
  Future<void> encargo(
    String estado, {
    String entrega = '2026-10-30',
    int saldo = 0,
    String? listo,
    String? id,
    String creadoEn = marca,
  }) => insertarEncargo(
    base,
    id: id ?? 'e${++siguiente}',
    clienteId: 'ana',
    creadoEn: creadoEn,
    estado: estado,
    entregaAcordada: entrega,
    saldoCentimos: saldo,
    listo: listo,
  );

  group('resumen', () {
    test('activos: ingresado, en proceso, listo y pausado (P2)', () async {
      for (final estado in [
        'INGRESADO',
        'EN_PROCESO',
        'LISTO',
        'PAUSADO',
        'ENTREGADO',
        'CANCELADO',
      ]) {
        await encargo(estado);
      }

      expect((await dashboard.observarResumen().first).activos, 4);
    });

    test('saldo: entregados fiados sí, cancelados no, a favor no resta (P1)', () async {
      await encargo('EN_PROCESO', saldo: 3000);
      await encargo('ENTREGADO', saldo: 2000);
      await encargo('CANCELADO', saldo: 9900);
      await encargo('LISTO', saldo: -500);

      expect((await dashboard.observarResumen().first).saldoPendiente, Monto.desdeCentimos(5000));
    });

    test('sin encargos: cero y S/ 0', () async {
      final resumen = await dashboard.observarResumen().first;

      expect([resumen.activos, resumen.saldoPendiente], [0, Monto.cero]);
    });
  });

  group('pendientes del día', () {
    List<String> ids(List<dynamic> filas) => [for (final f in filas) f.id as String];

    test('atrasados del más antiguo al más reciente, con el nombre del cliente', () async {
      await encargo('EN_PROCESO', id: 'ayer', entrega: '2026-10-22');
      await encargo('PAUSADO', id: 'semana', entrega: '2026-10-16');
      await encargo('INGRESADO', id: 'antier', entrega: '2026-10-21');

      final dia = await dashboard.observarPendientes(hoy).first;

      expect(ids(dia.atrasados), ['semana', 'antier', 'ayer']);
      expect(dia.atrasados.first.clienteNombre, 'Ana García');
      expect(dia.entregasHoy, isEmpty);
    });

    test('no son atrasados: listos sin recoger (P4), entregados ni cancelados', () async {
      await encargo('LISTO', entrega: '2026-10-20', listo: '2026-10-19');
      await encargo('ENTREGADO', entrega: '2026-10-20', listo: '2026-10-20');
      await encargo('CANCELADO', entrega: '2026-10-20');

      final dia = await dashboard.observarPendientes(hoy).first;

      expect(dia.atrasados, isEmpty);
      expect(dia.entregasHoy, isEmpty);
    });

    test('entregas de hoy: sin cerrar, lo ya entregado hoy no está', () async {
      await encargo('LISTO', id: 'listo', entrega: '2026-10-23', listo: '2026-10-22');
      await encargo('EN_PROCESO', id: 'proceso', entrega: '2026-10-23');
      await encargo('ENTREGADO', entrega: '2026-10-23', listo: '2026-10-23');
      await encargo('CANCELADO', entrega: '2026-10-23');
      await encargo('EN_PROCESO', entrega: '2026-10-24');

      final dia = await dashboard.observarPendientes(hoy).first;

      expect(ids(dia.entregasHoy), ['listo', 'proceso']);
      expect(dia.atrasados, isEmpty);
    });

    test('se actualiza solo: marcar listo saca al encargo de atrasados', () async {
      await encargo('EN_PROCESO', id: 'ayer', entrega: '2026-10-22');
      final vistos = <int>[];
      final sub = dashboard.observarPendientes(hoy).listen((d) => vistos.add(d.atrasados.length));
      await pumpEventQueue();

      await (base.update(base.encargos)..where((e) => e.id.equals('ayer'))).write(
        const EncargosCompanion(fechaListo: Value('2026-10-23'), estado: Value('LISTO')),
      );
      await pumpEventQueue();
      await sub.cancel();

      expect(vistos, [1, 0]);
    });
  });

  group('listas de los números (S5b)', () {
    List<String> ids(List<dynamic> filas) => [for (final f in filas) f.id as String];

    test('activos: los mismos que cuenta el resumen, por fecha de entrega', () async {
      await encargo('LISTO', id: 'jueves', entrega: '2026-10-29', listo: '2026-10-22');
      await encargo('PAUSADO', id: 'ayer', entrega: '2026-10-22');
      await encargo('INGRESADO', id: 'lunes', entrega: '2026-10-26');
      await encargo('ENTREGADO', entrega: '2026-10-20', listo: '2026-10-20');
      await encargo('CANCELADO', entrega: '2026-10-20');

      final lista = await dashboard.observarLista(FiltroEncargos.activos).first;

      expect(ids(lista), ['ayer', 'lunes', 'jueves']);
      expect(lista.length, (await dashboard.observarResumen().first).activos);
    });

    test('saldo: de la deuda mayor a la menor, con fiados; suma lo mismo que arriba', () async {
      await encargo('EN_PROCESO', id: 'poco', saldo: 1000);
      await encargo('ENTREGADO', id: 'fiado', saldo: 4000, listo: '2026-10-20');
      await encargo('LISTO', id: 'medio', saldo: 2500, listo: '2026-10-20');
      await encargo('CANCELADO', saldo: 9900);
      await encargo('EN_PROCESO', saldo: -300);
      await encargo('EN_PROCESO');

      final lista = await dashboard.observarLista(FiltroEncargos.conSaldo).first;

      expect(ids(lista), ['fiado', 'medio', 'poco']);
      final suma = lista.fold(Monto.cero, (total, e) => total + e.saldoPendiente);
      expect(suma, (await dashboard.observarResumen().first).saldoPendiente);
    });
  });

  test('el filtro de la ruta: "activos" y "saldo"; otro no existe', () {
    expect(FiltroEncargos.desde('activos'), FiltroEncargos.activos);
    expect(FiltroEncargos.desde('saldo'), FiltroEncargos.conSaldo);
    expect(FiltroEncargos.desde('otro'), isNull);
  });
}
