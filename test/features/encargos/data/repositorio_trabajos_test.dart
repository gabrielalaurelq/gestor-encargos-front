import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/encargos/data/repositorio_trabajos.dart';
import 'package:gestor_encargos/features/encargos/domain/trabajo.dart';
import 'package:gestor_encargos/features/servicios/domain/servicio.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/encargos_prueba.dart';

const marca = '2026-10-22T15:00:00.000Z';

void main() {
  late BaseDatos base;
  late Outbox outbox;
  late RepositorioTrabajos trabajos;
  late int siguiente;

  setUp(() async {
    base = BaseDatos(NativeDatabase.memory());
    outbox = Outbox(base);
    siguiente = 0;
    trabajos = RepositorioTrabajos(
      base: base,
      outbox: outbox,
      nuevoId: () => 't${++siguiente}',
      reloj: () => DateTime.utc(2026, 10, 22, 15, 0, siguiente),
    );
    await insertarEncargo(base, id: 'e1', clienteId: 'ana', creadoEn: marca);
  });
  tearDown(() async {
    await outbox.cerrar();
    await base.close();
  });

  const basta = Servicio(
    id: 's1',
    nombre: 'Basta de jean',
    precio: Monto.desdeCentimos(2000),
    activo: true,
  );

  Future<EncargoFila> encargo() => base.select(base.encargos).getSingle();
  Future<List<OperacionOutbox>> cola() => base.select(base.operacionesOutbox).get();
  List<int> montos(EncargoFila e) => [e.precioTotal, e.descuento, e.saldoPendiente];

  group('agregar', () {
    test('del catálogo: copia nombre y precio, recalcula y solo envía el servicio', () async {
      final trabajo = await trabajos.agregarDelCatalogo('e1', basta);

      final fila = await base.select(base.trabajos).getSingle();
      expect([fila.descripcion, fila.precio, fila.servicioId], ['Basta de jean', 2000, 's1']);
      expect(trabajo.delCatalogo, isTrue);
      expect(montos(await encargo()), [2000, 0, 2000]);
      final op = (await cola()).single;
      expect(
        [op.tipo, op.metodo, op.ruta, op.entidadId, op.encargoId],
        [TiposTrabajo.crear, 'POST', '/encargos/e1/trabajos', 't1', 'e1'],
      );
      expect(op.cuerpoJson, {'id': 't1', 'servicio_id': 's1'});
    });

    test('personalizado: descripción limpia y precio en soles; el S/ 0 vale', () async {
      await trabajos.agregarPersonalizado(
        'e1',
        descripcion: '  Confección  ',
        precio: Monto.desde('180.50'),
      );
      await trabajos.agregarPersonalizado('e1', descripcion: 'Retoque', precio: Monto.cero);

      expect(montos(await encargo()), [18050, 0, 18050]);
      final ops = await cola();
      expect(ops.first.cuerpoJson, {'id': 't1', 'descripcion': 'Confección', 'precio': 180.5});
      expect(ops.last.cuerpoJson, {'id': 't2', 'descripcion': 'Retoque', 'precio': 0});
    });

    test('el saldo descuenta lo ya pagado', () async {
      await insertarPago(base, id: 'p1', encargoId: 'e1', centimos: 500);

      await trabajos.agregarDelCatalogo('e1', basta);

      expect(montos(await encargo()), [2000, 0, 1500]);
    });

    test('un servicio desactivado no se ofrece', () async {
      const inactivo = Servicio(id: 's2', nombre: 'X', precio: Monto.cero, activo: false);

      expect(
        () => trabajos.agregarDelCatalogo('e1', inactivo),
        throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'SERVICIO_NO_DISPONIBLE')),
      );
    });

    test('sin descripción no se guarda nada', () async {
      await expectLater(
        trabajos.agregarPersonalizado('e1', descripcion: ' ', precio: Monto.cero),
        throwsA(isA<ValorInvalido>()),
      );
      expect(await cola(), isEmpty);
    });
  });

  group('editar', () {
    test('personalizado: PATCH solo con lo que cambió y recálculo', () async {
      final trabajo = await trabajos.agregarPersonalizado(
        'e1',
        descripcion: 'Confección',
        precio: Monto.desde(100),
      );

      expect(
        await trabajos.editar(trabajo, descripcion: 'Confección', precio: Monto.desde(120)),
        isTrue,
      );

      expect(montos(await encargo()), [12000, 0, 12000]);
      expect((await cola()).last.cuerpoJson, {'precio': 120});
      expect((await cola()).last.ruta, '/encargos/e1/trabajos/t1');
    });

    test('sin cambios no encola nada', () async {
      final trabajo = await trabajos.agregarDelCatalogo('e1', basta);

      expect(await trabajos.editar(trabajo, descripcion: 'Basta de jean'), isFalse);
      expect(await cola(), hasLength(1));
    });

    test('del catálogo: la descripción sí, el precio no (invariante 13)', () async {
      final trabajo = await trabajos.agregarDelCatalogo('e1', basta);

      await trabajos.editar(trabajo, descripcion: 'Basta de jean azul');
      expect((await cola()).last.cuerpoJson, {'descripcion': 'Basta de jean azul'});

      expect(
        () => trabajos.editar(trabajo, descripcion: 'Basta', precio: Monto.desde(25)),
        throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'TRABAJO_PRECIO_BLOQUEADO')),
      );
    });
  });

  test('eliminar: borra con sus materiales, ajusta el descuento y encola el DELETE', () async {
    final trabajo = await trabajos.agregarDelCatalogo('e1', basta);
    await (base.update(base.encargos)).write(const EncargosCompanion(descuento: Value(300)));
    await base
        .into(base.materiales)
        .insert(
          MaterialesCompanion.insert(
            id: 'm1',
            creadoEn: marca,
            actualizadoEn: marca,
            trabajoId: 't1',
            nombre: 'Hilo',
          ),
        );

    await trabajos.eliminar(trabajo);

    expect(await base.select(base.trabajos).get(), isEmpty);
    expect(await base.select(base.materiales).get(), isEmpty);
    expect(montos(await encargo()), [
      0,
      0,
      0,
    ], reason: 'PRD 4: el descuento no deja total negativo');
    final op = (await cola()).last;
    expect(
      [op.tipo, op.metodo, op.ruta, op.cuerpo],
      [TiposTrabajo.eliminar, 'DELETE', '/encargos/e1/trabajos/t1', null],
    );
  });

  test('las escrituras locales no adelantan la versión del servidor', () async {
    await trabajos.agregarDelCatalogo('e1', basta);

    expect((await encargo()).actualizadoEn, marca);
    expect((await base.select(base.trabajos).getSingle()).actualizadoEn, sinVersionDelServidor);
  });

  for (final estado in ['ENTREGADO', 'CANCELADO']) {
    test('$estado: los trabajos no cambian (decisión del usuario)', () async {
      final trabajo = await trabajos.agregarDelCatalogo('e1', basta);
      await (base.update(base.encargos)).write(EncargosCompanion(estado: Value(estado)));
      final cerrado = isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'ENCARGO_CERRADO');

      await expectLater(trabajos.agregarDelCatalogo('e1', basta), throwsA(cerrado));
      await expectLater(trabajos.editar(trabajo, descripcion: 'Otra'), throwsA(cerrado));
      await expectLater(trabajos.eliminar(trabajo), throwsA(cerrado));
      expect(await cola(), hasLength(1));
      expect(await base.select(base.trabajos).get(), hasLength(1));
    });
  }

  test('observar los lista en el orden en que se agregaron', () async {
    await trabajos.agregarPersonalizado('e1', descripcion: 'B', precio: Monto.cero);
    await trabajos.agregarPersonalizado('e1', descripcion: 'A', precio: Monto.cero);

    final lista = await trabajos.observar('e1').first;
    expect([for (final Trabajo t in lista) t.descripcion], ['B', 'A']);
  });

  group('vínculo con un objeto (S3d2)', () {
    Future<void> objeto(String id, {String encargoId = 'e1'}) => base
        .into(base.objetosRecibidos)
        .insert(
          ObjetosRecibidosCompanion.insert(
            id: id,
            creadoEn: marca,
            actualizadoEn: marca,
            encargoId: encargoId,
            descripcion: 'Objeto $id',
          ),
        );

    Matcher rechazo(String codigo) =>
        throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', codigo));

    test('agregar con objeto: se guarda y viaja; sin objeto no viaja la clave', () async {
      await objeto('o1');

      final conObjeto = await trabajos.agregarDelCatalogo('e1', basta, objetoId: 'o1');
      await trabajos.agregarPersonalizado(
        'e1',
        descripcion: 'Zurcido',
        precio: Monto.desde(10),
        objetoId: 'o1',
      );
      await trabajos.agregarPersonalizado('e1', descripcion: 'Suelto', precio: Monto.cero);

      expect(conObjeto.objetoRecibidoId, 'o1');
      final lista = await trabajos.observar('e1').first;
      expect([for (final t in lista) t.objetoRecibidoId], ['o1', 'o1', null]);
      final cuerpos = [for (final op in await cola()) op.cuerpoJson];
      expect(cuerpos[0], {'id': 't1', 'servicio_id': 's1', 'objeto_recibido_id': 'o1'});
      expect(cuerpos[1], containsPair('objeto_recibido_id', 'o1'));
      expect(cuerpos[2]!.containsKey('objeto_recibido_id'), isFalse);
    });

    test('un objeto de otro encargo: OBJETO_NO_EN_ENCARGO y nada se guarda', () async {
      await insertarEncargo(base, id: 'e2', clienteId: 'ana', numero: 2, creadoEn: marca);
      await objeto('o9', encargoId: 'e2');

      await expectLater(
        trabajos.agregarDelCatalogo('e1', basta, objetoId: 'o9'),
        rechazo('OBJETO_NO_EN_ENCARGO'),
      );
      expect(await base.select(base.trabajos).get(), isEmpty);
      expect(await cola(), isEmpty);
    });

    test('editar: vincular, cambiar y quitar; sin objetoId no se toca', () async {
      await objeto('o1');
      await objeto('o2');
      var trabajo = await trabajos.agregarDelCatalogo('e1', basta);

      expect(await trabajos.editar(trabajo, descripcion: 'Basta de jean', objetoId: 'o1'), isTrue);
      expect((await cola()).last.cuerpoJson, {'objeto_recibido_id': 'o1'});
      trabajo = (await trabajos.observar('e1').first).single;
      expect(trabajo.objetoRecibidoId, 'o1');

      expect(await trabajos.editar(trabajo, descripcion: 'Basta azul'), isTrue);
      expect((await cola()).last.cuerpoJson, {'descripcion': 'Basta azul'});
      trabajo = (await trabajos.observar('e1').first).single;
      expect(trabajo.objetoRecibidoId, 'o1', reason: 'sin objetoId el vínculo se queda');

      await trabajos.editar(trabajo, descripcion: 'Basta azul', objetoId: 'o2');
      expect((await cola()).last.cuerpoJson, {'objeto_recibido_id': 'o2'});
      trabajo = (await trabajos.observar('e1').first).single;

      await trabajos.editar(trabajo, descripcion: 'Basta azul', objetoId: null);
      expect((await cola()).last.cuerpoJson, {'objeto_recibido_id': null});
      expect((await trabajos.observar('e1').first).single.objetoRecibidoId, isNull);
      expect(montos(await encargo()), [2000, 0, 2000], reason: 'el dinero no cambia');
    });

    test('editar hacia un objeto que no está: se rechaza sin escribir', () async {
      final trabajo = await trabajos.agregarDelCatalogo('e1', basta);

      await expectLater(
        trabajos.editar(trabajo, descripcion: 'Basta de jean', objetoId: 'fantasma'),
        rechazo('OBJETO_NO_EN_ENCARGO'),
      );
      expect(await cola(), hasLength(1));
    });

    test('un vínculo que ya no está no impide editar lo demás', () async {
      await base
          .into(base.trabajos)
          .insert(
            TrabajosCompanion.insert(
              id: 'tx',
              creadoEn: marca,
              actualizadoEn: marca,
              encargoId: 'e1',
              objetoRecibidoId: const Value('borrado'),
              descripcion: 'Huérfano',
              precio: 0,
            ),
          );
      final trabajo = (await trabajos.observar('e1').first).single;

      expect(await trabajos.editar(trabajo, descripcion: 'Huérfano 2'), isTrue);
      expect((await cola()).single.cuerpoJson, {'descripcion': 'Huérfano 2'});
    });
  });
}
