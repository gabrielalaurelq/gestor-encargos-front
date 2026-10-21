import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/clientes/data/repositorio_clientes.dart';
import 'package:gestor_encargos/features/clientes/domain/cliente.dart';
import 'package:gestor_encargos/shared/domain/telefono.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/sync/bajada.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/adaptador_falso.dart';

void main() {
  late BaseDatos base;
  late Outbox outbox;
  late RepositorioClientes repositorio;
  var ids = 0;

  setUp(() {
    base = BaseDatos(NativeDatabase.memory());
    outbox = Outbox(base);
    ids = 0;
    repositorio = RepositorioClientes(base: base, outbox: outbox, nuevoId: () => 'c${++ids}');
  });
  tearDown(() async {
    await outbox.cerrar();
    await base.close();
  });

  Future<List<OperacionOutbox>> cola() => base.select(base.operacionesOutbox).get();
  Future<List<String>> buscar(String texto) async => [
    for (final c in await repositorio.buscar(texto).first) c.nombre,
  ];
  final celular = Telefono.peruano('987654321');

  group('crear', () {
    test('la fila y su POST quedan juntos, sin adelantar actualizado_en', () async {
      await repositorio.crear(nombre: ' María Núñez ', telefono: celular);

      final fila = await base.select(base.clientes).getSingle();
      expect(
        [fila.nombre, fila.nombreBusqueda, fila.telefono],
        ['María Núñez', 'maria nunez', '+51987654321'],
      );
      expect(fila.actualizadoEn, sinVersionDelServidor);
      final op = (await cola()).single;
      expect([op.metodo, op.ruta, op.entidadId], ['POST', '/clientes', 'c1']);
      expect(op.cuerpoJson, {'id': 'c1', 'nombre': 'María Núñez', 'telefono': '+51987654321'});
    });

    test('sin teléfono viaja como null (el backend lo admite)', () async {
      await repositorio.crear(nombre: 'Ana');

      expect((await cola()).single.cuerpoJson, containsPair('telefono', null));
    });

    test('nombre vacío no escribe nada', () async {
      await expectLater(repositorio.crear(nombre: ' '), throwsA(isA<ValorInvalido>()));

      expect(await base.select(base.clientes).get(), isEmpty);
      expect(await cola(), isEmpty);
    });
  });

  group('editar', () {
    late Cliente ana;
    setUp(() async => ana = await repositorio.crear(nombre: 'Ana', telefono: celular));

    test('PATCH solo con lo que cambió', () async {
      await repositorio.editar(ana, nombre: 'Ana Pérez', telefono: celular);

      final op = (await cola()).last;
      expect([op.metodo, op.ruta], ['PATCH', '/clientes/c1']);
      expect(op.cuerpoJson, {'nombre': 'Ana Pérez'});
      final fila = await base.select(base.clientes).getSingle();
      expect([fila.nombre, fila.nombreBusqueda], ['Ana Pérez', 'ana perez']);
      expect(fila.actualizadoEn, sinVersionDelServidor);
    });

    test('quitar el teléfono viaja como null explícito (ausente sería "no tocar")', () async {
      await repositorio.editar(ana, nombre: 'Ana');

      expect((await cola()).last.cuerpoJson, {'telefono': null});
      expect((await base.select(base.clientes).getSingle()).telefono, isNull);
    });

    test('sin cambios no encola nada', () async {
      await repositorio.editar(ana, nombre: ' Ana ', telefono: celular);

      expect((await cola()).length, 1, reason: 'solo el alta');
    });
  });

  group('buscar', () {
    setUp(() async {
      await repositorio.crear(nombre: 'María Núñez', telefono: celular);
      await repositorio.crear(nombre: 'ana pérez');
      await repositorio.crear(nombre: 'Ángel Ruiz', telefono: Telefono.e164('+34612345678'));
      await repositorio.crear(nombre: 'Taller 50% off');
    });

    test('vacío: todos, alfabético sin importar mayúsculas ni tildes', () async {
      expect(await buscar(''), ['ana pérez', 'Ángel Ruiz', 'María Núñez', 'Taller 50% off']);
    });

    test('parte del nombre, sin importar mayúsculas ni tildes', () async {
      expect(await buscar('MARIA'), ['María Núñez']);
      expect(await buscar('nunez'), ['María Núñez']);
      expect(await buscar('ría'), ['María Núñez'], reason: 'en medio de una palabra');
      expect(await buscar('an'), ['ana pérez', 'Ángel Ruiz']);
    });

    test('por dígitos del teléfono, con o sin espacios y prefijo', () async {
      expect(await buscar('987 65'), ['María Núñez']);
      expect(await buscar('+51 9876'), ['María Núñez']);
      expect(await buscar('612'), ['Ángel Ruiz']);
    });

    test('% y _ se buscan como texto, no como comodines', () async {
      expect(await buscar('50%'), ['Taller 50% off']);
      expect(await buscar('_'), isEmpty);
    });

    test('es reactiva: lo que se agrega después aparece solo', () async {
      final listas = <List<String>>[];
      final sub = repositorio.buscar('ma').listen((l) => listas.add([for (final c in l) c.nombre]));
      await pumpEventQueue();

      await repositorio.crear(nombre: 'Mateo');
      await pumpEventQueue();

      expect(listas.last, ['María Núñez', 'Mateo']);
      await sub.cancel();
    });
  });

  test('conTelefono encuentra a quien ya lo tiene, menos al propio cliente', () async {
    final ana = await repositorio.crear(nombre: 'Ana', telefono: celular);
    await repositorio.crear(nombre: 'Luis');

    expect([for (final c in await repositorio.conTelefono(celular)) c.nombre], ['Ana']);
    expect(await repositorio.conTelefono(celular, excepto: ana.id), isEmpty);
  });

  test('lo que baja del servidor también se puede buscar sin tildes', () async {
    final backend = AdaptadorFalso()
      ..cuando(
        'GET /sync',
        (_) => const Respuesta(200, {
          'servidor_timestamp': '2026-10-21T10:00:00.000Z',
          'has_more': false,
          'cambios': {
            'clientes': [
              {
                'id': 'remoto',
                'nombre': 'Jesús Peña',
                'telefono': null,
                'creado_en': '2026-10-21T09:00:00.000Z',
                'actualizado_en': '2026-10-21T09:00:00.000Z',
              },
            ],
          },
        }),
      );

    await Bajada(api: clienteApiDePrueba(backend), base: base).bajar();

    expect(await buscar('jesus pena'), ['Jesús Peña']);
  });
}
