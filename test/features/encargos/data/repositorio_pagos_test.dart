import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/encargos/data/repositorio_pagos.dart';
import 'package:gestor_encargos/features/encargos/domain/pago.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/encargos_prueba.dart';

const marca = '2026-10-01T15:00:00.000Z';
const yape = 3;

void main() {
  late BaseDatos base;
  late Outbox outbox;
  late RepositorioPagos pagos;
  late DateTime ahora;
  late int siguiente;

  setUp(() async {
    base = BaseDatos(NativeDatabase.memory());
    outbox = Outbox(base);
    siguiente = 0;
    ahora = DateTime.utc(2026, 10, 22, 15);
    pagos = RepositorioPagos(
      base: base,
      outbox: outbox,
      nuevoId: () => 'p${++siguiente}',
      reloj: () => ahora.add(Duration(seconds: siguiente)),
    );
    await insertarOrigenes(base, inactivos: {'Plin'});
  });
  tearDown(() async {
    await outbox.cerrar();
    await base.close();
  });

  /// Un encargo con un trabajo de S/ 50 (sin pagos) en el estado pedido: el
  /// recálculo parte de la suma de trabajos, como el backend.
  Future<void> encargo({String estado = 'EN_PROCESO'}) async {
    await insertarEncargo(
      base,
      id: 'e1',
      clienteId: 'ana',
      creadoEn: marca,
      estado: estado,
      precioCentimos: 5000,
      saldoCentimos: 5000,
    );
    await base
        .into(base.trabajos)
        .insert(
          TrabajosCompanion.insert(
            id: 't1',
            creadoEn: marca,
            actualizadoEn: marca,
            encargoId: 'e1',
            descripcion: 'Confección',
            precio: 5000,
          ),
        );
  }

  Future<int> saldo() async => (await base.select(base.encargos).getSingle()).saldoPendiente;
  Future<List<OperacionOutbox>> cola() => base.select(base.operacionesOutbox).get();

  Future<Pago> registrar(String monto, {int origenId = yape, TipoPago tipo = TipoPago.adelanto}) =>
      pagos.registrar('e1', monto: Monto.desde(monto), origenId: origenId, tipo: tipo);

  Matcher rechazo(String codigo) =>
      throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', codigo));

  group('registrar', () {
    test('baja el saldo y encola el POST con la fecha del teléfono', () async {
      await encargo();

      final pago = await registrar('20');

      expect(await saldo(), 3000);
      final fila = await base.select(base.pagos).getSingle();
      expect(
        [fila.monto, fila.origenId, fila.tipo, fila.fecha],
        [2000, yape, 'ADELANTO', '2026-10-22'],
      );
      expect(fila.actualizadoEn, sinVersionDelServidor);
      expect(pago.origenNombre, 'Yape');
      final op = (await cola()).single;
      expect(
        [op.tipo, op.metodo, op.ruta, op.entidadId, op.encargoId],
        [TiposPago.registrar, 'POST', '/encargos/e1/pagos', 'p1', 'e1'],
      );
      expect(op.cuerpoJson, {
        'id': 'p1',
        'monto': 20,
        'origen_id': yape,
        'tipo': 'ADELANTO',
        'fecha': '2026-10-22',
      });
    });

    test('la fecha es el día en Lima: las 22:00 del 22 son el 23 en UTC', () async {
      await encargo();
      ahora = DateTime.utc(2026, 10, 23, 3);

      await registrar('10');

      expect((await base.select(base.pagos).getSingle()).fecha, '2026-10-22');
    });

    test('PRD 5: más que el saldo se registra y queda a favor del cliente', () async {
      await encargo();

      await registrar('80', tipo: TipoPago.pago);

      expect(await saldo(), -3000);
      expect((await cola()).single.cuerpoJson!['tipo'], 'PAGO');
    });

    test('PRD 5: sin trabajos (total S/ 0) también se registra', () async {
      await insertarEncargo(base, id: 'e1', clienteId: 'ana', creadoEn: marca);

      await registrar('15');

      expect(await saldo(), -1500);
    });

    test('monto cero: PAGO_MONTO_INVALIDO y nada se guarda', () async {
      await encargo();

      await expectLater(registrar('0'), rechazo('PAGO_MONTO_INVALIDO'));
      expect(await base.select(base.pagos).get(), isEmpty);
      expect(await cola(), isEmpty);
    });

    test('origen desactivado o desconocido: ORIGEN_PAGO_INVALIDO', () async {
      await encargo();

      await expectLater(registrar('10', origenId: 4), rechazo('ORIGEN_PAGO_INVALIDO'));
      await expectLater(registrar('10', origenId: 99), rechazo('ORIGEN_PAGO_INVALIDO'));
      expect(await cola(), isEmpty);
    });

    test('entregado: sí se cobra (entregó fiado; decisión del usuario)', () async {
      await encargo(estado: 'ENTREGADO');

      await registrar('50', tipo: TipoPago.pago);

      expect(await saldo(), 0);
    });

    test('cancelado: no recibe pagos', () async {
      await encargo(estado: 'CANCELADO');

      await expectLater(registrar('10'), rechazo('ENCARGO_CERRADO'));
      expect(await base.select(base.pagos).get(), isEmpty);
    });
  });

  group('eliminar', () {
    test('el saldo vuelve a subir y viaja el DELETE', () async {
      await encargo();
      final pago = await registrar('20');

      await pagos.eliminar(pago);

      expect(await saldo(), 5000);
      expect(await base.select(base.pagos).get(), isEmpty);
      final op = (await cola()).last;
      expect(
        [op.tipo, op.metodo, op.ruta, op.entidadId, op.encargoId, op.cuerpo],
        [TiposPago.eliminar, 'DELETE', '/encargos/e1/pagos/p1', 'p1', 'e1', null],
      );
    });

    test('cancelado: los pagos se quedan como están', () async {
      await encargo(estado: 'CANCELADO');
      await insertarPago(base, id: 'p9', encargoId: 'e1', centimos: 1000);
      final pago = (await pagos.observar('e1').first).single;

      await expectLater(pagos.eliminar(pago), rechazo('ENCARGO_CERRADO'));
      expect(await base.select(base.pagos).get(), hasLength(1));
    });
  });

  group('observar', () {
    test('en orden, con el nombre del origen aunque esté desactivado', () async {
      await encargo();
      await registrar('10');
      await base
          .into(base.pagos)
          .insert(
            PagosCompanion.insert(
              id: 'viejo',
              creadoEn: marca,
              actualizadoEn: marca,
              encargoId: 'e1',
              monto: 500,
              origenId: 4,
              tipo: 'PAGO',
              fecha: '2026-10-01',
            ),
          );

      final lista = await pagos.observar('e1').first;

      expect([for (final p in lista) p.id], ['viejo', 'p1']);
      expect([for (final p in lista) p.origenNombre], ['Plin', 'Yape']);
      expect(lista.first.tipo, TipoPago.pago);
      expect(lista.first.fecha, DateTime.utc(2026, 10, 1));
    });

    test('sin el catálogo bajado, el pago se ve sin nombre de origen', () async {
      await encargo();
      await base.delete(base.origenesPago).go();
      await insertarPago(base, id: 'p9', encargoId: 'e1', centimos: 1000);

      expect((await pagos.observar('e1').first).single.origenNombre, isNull);
    });

    test('para registrar solo se ofrecen los activos', () async {
      final origenes = await pagos.observarOrigenesActivos().first;

      expect([for (final o in origenes) o.nombre], ['Efectivo', 'Transferencia', 'Yape']);
    });
  });
}
