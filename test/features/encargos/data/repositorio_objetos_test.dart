import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/encargos/data/repositorio_objetos.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/encargos_prueba.dart';

const marca = '2026-10-01T15:00:00.000Z';

void main() {
  late BaseDatos base;
  late Outbox outbox;
  late RepositorioObjetos objetos;
  late int siguiente;

  setUp(() async {
    base = BaseDatos(NativeDatabase.memory());
    outbox = Outbox(base);
    siguiente = 0;
    objetos = RepositorioObjetos(
      base: base,
      outbox: outbox,
      nuevoId: () => 'o${++siguiente}',
      reloj: () => DateTime.utc(2026, 10, 22, 15, 0, siguiente),
    );
  });
  tearDown(() async {
    await outbox.cerrar();
    await base.close();
  });

  Future<void> encargo({String estado = 'EN_PROCESO'}) =>
      insertarEncargo(base, id: 'e1', clienteId: 'ana', creadoEn: marca, estado: estado);

  Future<List<OperacionOutbox>> cola() => base.select(base.operacionesOutbox).get();

  Matcher rechazo(String codigo) =>
      throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', codigo));

  Future<void> trabajo(String id, {String? objeto}) => base
      .into(base.trabajos)
      .insert(
        TrabajosCompanion.insert(
          id: id,
          creadoEn: marca,
          actualizadoEn: marca,
          encargoId: 'e1',
          objetoRecibidoId: Value(objeto),
          descripcion: 'Trabajo $id',
          precio: 1000,
        ),
      );

  test('agregar: descripción limpia, en orden, y el POST con el id del teléfono', () async {
    await encargo();

    await objetos.agregar('e1', descripcion: '  Pantalón azul ');
    await objetos.agregar('e1', descripcion: 'Tela del cliente');

    final lista = await objetos.observar('e1').first;
    expect([for (final o in lista) o.descripcion], ['Pantalón azul', 'Tela del cliente']);
    expect(
      (await base.select(base.objetosRecibidos).get()).first.actualizadoEn,
      sinVersionDelServidor,
    );
    final op = (await cola()).first;
    expect(
      [op.tipo, op.metodo, op.ruta, op.entidadId, op.encargoId],
      [TiposObjeto.crear, 'POST', '/encargos/e1/objetos', 'o1', 'e1'],
    );
    expect(op.cuerpoJson, {'id': 'o1', 'descripcion': 'Pantalón azul'});
  });

  test('descripción vacía: OBJETO_DESCRIPCION_VACIA y nada se guarda', () async {
    await encargo();

    await expectLater(
      objetos.agregar('e1', descripcion: '   '),
      rechazo('OBJETO_DESCRIPCION_VACIA'),
    );
    expect(await cola(), isEmpty);
  });

  test('editar: PATCH solo si cambió', () async {
    await encargo();
    final objeto = await objetos.agregar('e1', descripcion: 'Pantalón');

    expect(await objetos.editar(objeto, descripcion: ' Pantalón '), isFalse);
    expect(await objetos.editar(objeto, descripcion: 'Pantalón azul'), isTrue);

    final op = (await cola()).last;
    expect([op.tipo, op.metodo, op.ruta], [TiposObjeto.editar, 'PATCH', '/encargos/e1/objetos/o1']);
    expect(op.cuerpoJson, {'descripcion': 'Pantalón azul'});
    expect((await objetos.observar('e1').first).single.descripcion, 'Pantalón azul');
  });

  test('eliminar: sus trabajos se quedan sin objeto y sus fotos se van (cascada)', () async {
    await encargo();
    final objeto = await objetos.agregar('e1', descripcion: 'Pantalón');
    await trabajo('t1', objeto: 'o1');
    await trabajo('t2');
    await base
        .into(base.fotos)
        .insert(
          FotosCompanion.insert(
            id: 'f1',
            creadoEn: marca,
            actualizadoEn: marca,
            encargoId: 'e1',
            objetoRecibidoId: const Value('o1'),
          ),
        );

    await objetos.eliminar(objeto);

    expect(await base.select(base.objetosRecibidos).get(), isEmpty);
    expect(await base.select(base.fotos).get(), isEmpty);
    final trabajos = await base.select(base.trabajos).get();
    expect([for (final t in trabajos) t.objetoRecibidoId], [null, null]);
    final op = (await cola()).last;
    expect(
      [op.tipo, op.metodo, op.ruta, op.cuerpo],
      [TiposObjeto.eliminar, 'DELETE', '/encargos/e1/objetos/o1', null],
    );
  });

  test('entregado o cancelado: los objetos no cambian (decisión del usuario)', () async {
    await encargo(estado: 'ENTREGADO');

    await expectLater(objetos.agregar('e1', descripcion: 'Pantalón'), rechazo('ENCARGO_CERRADO'));
    expect(await base.select(base.objetosRecibidos).get(), isEmpty);
  });
}
