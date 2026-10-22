import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/clientes/data/repositorio_clientes.dart';
import 'package:gestor_encargos/features/encargos/data/repositorio_encargos.dart';
import 'package:gestor_encargos/features/encargos/data/repositorio_pagos.dart';
import 'package:gestor_encargos/features/encargos/data/repositorio_trabajos.dart';
import 'package:gestor_encargos/features/servicios/data/repositorio_servicios.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/domain/telefono.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/infrastructure/http/error_api.dart';
import 'package:gestor_encargos/shared/sync/descarte.dart';
import 'package:gestor_encargos/shared/sync/numeracion.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../helpers/adaptador_falso.dart';
import '../../helpers/encargos_prueba.dart';

const marca = '2026-10-22T15:00:00.000Z';

void main() {
  late AdaptadorFalso backend;
  late BaseDatos base;
  late Outbox outbox;
  late Descarte descarte;

  setUp(() {
    backend = AdaptadorFalso();
    base = BaseDatos(NativeDatabase.memory());
    outbox = Outbox(base);
    descarte = Descarte(base: base, api: clienteApiDePrueba(backend));
  });
  tearDown(() async {
    await outbox.cerrar();
    await base.close();
  });

  RepositorioClientes clientes() =>
      RepositorioClientes(base: base, outbox: outbox, nuevoId: () => 'ana');

  /// El servidor rechaza la operación más antigua de la cola: se aparta.
  Future<OperacionApartada> rechazar({int indice = 0}) async {
    final ops = await (base.select(base.operacionesOutbox)).get();
    await outbox.apartar(
      ops[indice].id,
      const ErrorRechazado(codigo: 'X', mensaje: 'No', status: 422),
    );
    return (await outbox.apartadas().first).single;
  }

  Future<List<OperacionOutbox>> cola() => base.select(base.operacionesOutbox).get();

  test('los tipos registrados son los que encolan las features', () {
    expect(
      tiposDeOperacion.keys,
      containsAll(<String>[
        TiposCliente.crear,
        TiposCliente.editar,
        TiposServicio.crear,
        TiposServicio.editar,
        TiposEncargo.crear,
        TiposEncargo.editar,
        TiposTrabajo.crear,
        TiposTrabajo.editar,
        TiposTrabajo.eliminar,
        TiposPago.registrar,
        TiposPago.eliminar,
      ]),
    );
  });

  group('cliente', () {
    test('edición rechazada: vuelve a la versión del servidor y sale de la cola', () async {
      final ana = await clientes().crear(nombre: 'Ana');
      await outbox.completar((await cola()).single.id); // el alta ya subió
      await clientes().editar(ana, nombre: 'Ana Rechazada');
      final apartada = await rechazar();
      backend.cuando(
        'GET /clientes/ana',
        (_) => const Respuesta(200, {
          'id': 'ana',
          'nombre': 'Ana Pérez',
          'telefono': '+51987654321',
          'creado_en': marca,
          'actualizado_en': marca,
          'historial': {'total_encargos': 0, 'total_pagado': 0, 'ultimo_encargo_en': null},
        }),
      );

      await descarte.descartar(apartada);

      final fila = await base.select(base.clientes).getSingle();
      expect(
        [fila.nombre, fila.nombreBusqueda, fila.telefono],
        ['Ana Pérez', 'ana perez', '+51987654321'],
      );
      expect(await cola(), isEmpty);
    });

    test('alta rechazada (404): la fila local se borra con lo que dependía de ella', () async {
      await clientes().crear(nombre: 'Ana', telefono: Telefono.peruano('987654321'));
      final ana = (await clientes().buscar('').first).single;
      await clientes().editar(ana, nombre: 'Ana P.');
      final apartada = await rechazar();
      backend.cuando('GET /clientes/ana', (_) => Respuesta.error(404, 'NO_ENCONTRADO'));

      await descarte.descartar(apartada);

      expect(await base.select(base.clientes).get(), isEmpty);
      expect(await cola(), isEmpty, reason: 'la edición posterior también cae');
    });

    test('sin conexión no toca nada', () async {
      await clientes().crear(nombre: 'Ana');
      final apartada = await rechazar();
      backend.sinRed = true;

      await expectLater(descarte.descartar(apartada), throwsA(isA<SinConexion>()));

      expect((await base.select(base.clientes).getSingle()).nombre, 'Ana');
      expect((await cola()).single.apartadaCodigo, 'X');
    });
  });

  test('servicio: lo busca en el catálogo completo (no hay GET por id)', () async {
    final servicios = RepositorioServicios(base: base, outbox: outbox, nuevoId: () => 's1');
    await servicios.crear(nombre: 'Basta', precio: Monto.desde(15));
    await outbox.completar((await cola()).single.id);
    await servicios.cambiarPrecio('s1', Monto.desde(99));
    final apartada = await rechazar();
    backend.cuando('GET /servicios', (peticion) {
      expect(peticion.query['incluir_inactivos'], true);
      return const Respuesta(200, {
        'datos': [
          {
            'id': 's1',
            'nombre': 'Basta',
            'precio': 15,
            'activo': true,
            'creado_en': marca,
            'actualizado_en': marca,
          },
        ],
        'pagina': 1,
        'por_pagina': 100,
        'total': 1,
      });
    });

    await descarte.descartar(apartada);

    expect((await base.select(base.servicios).getSingle()).precio, 1500);
  });

  group('encargo', () {
    late RepositorioEncargos encargos;

    setUp(() {
      encargos = RepositorioEncargos(
        base: base,
        outbox: outbox,
        numeracion: Numeracion(base: base, api: clienteApiDePrueba(backend)),
        nuevoId: () => 'e1',
      );
    });

    Respuesta detalle({List<Map<String, Object?>> pagos = const []}) => Respuesta(200, {
      'id': 'e1',
      'cliente_id': 'ana',
      'numero': 47,
      'descripcion': 'Vestido de noche',
      'estado': 'EN_PROCESO',
      'precio_total': 300,
      'descuento': 0,
      'saldo_pendiente': 100,
      'fecha_entrega_prometida': '2026-10-24',
      'fecha_entrega_acordada': '2026-10-24',
      'fecha_listo': null,
      'fecha_entrega_real': null,
      'ubicacion_fisica': 'Cajón 3',
      'notas_generales': null,
      'creado_en': marca,
      'actualizado_en': marca,
      'objetos': <Object>[],
      'trabajos': <Object>[],
      'pagos': pagos,
      'notas': <Object>[],
      'fotos': <Object>[],
    });

    test('edición rechazada: el agregado queda como en el servidor, hijos incluidos', () async {
      await insertarEncargo(
        base,
        id: 'e1',
        clienteId: 'ana',
        creadoEn: marca,
        descripcion: 'Vestido',
      );
      // Un pago local que el servidor ya no tiene (lo borró otro teléfono).
      await insertarPago(base, id: 'viejo', encargoId: 'e1', centimos: 500);
      final actual = (await encargos.observar('e1').first)!;
      await encargos.editar(
        actual,
        descripcion: 'Vestido rechazado',
        fechaEntregaAcordada: actual.fechaEntregaAcordada,
        ubicacion: '',
        notas: '',
      );
      final apartada = await rechazar();
      backend.cuando(
        'GET /encargos/e1',
        (_) => detalle(
          pagos: [
            {
              'id': 'p1',
              'monto': 200,
              'origen_id': 1,
              'tipo': 'ADELANTO',
              'fecha': '2026-10-20',
              'creado_en': marca,
              'actualizado_en': marca,
            },
          ],
        ),
      );

      await descarte.descartar(apartada);

      final fila = await base.select(base.encargos).getSingle();
      expect(
        [fila.descripcion, fila.numero, fila.ubicacionFisica],
        ['Vestido de noche', 47, 'Cajón 3'],
      );
      final pagos = await base.select(base.pagos).get();
      expect([for (final p in pagos) (p.id, p.encargoId, p.monto)], [('p1', 'e1', 20000)]);
      expect(await cola(), isEmpty);
    });

    test('alta rechazada (404): se borra el encargo y la operación', () async {
      await encargos.crear(
        clienteId: 'ana',
        descripcion: 'Basta',
        fechaEntregaAcordada: DateTime.utc(2026, 10, 24),
      );
      final apartada = await rechazar();
      backend.cuando('GET /encargos/e1', (_) => Respuesta.error(404, 'NO_ENCONTRADO'));

      await descarte.descartar(apartada);

      expect(await base.select(base.encargos).get(), isEmpty);
      expect(await cola(), isEmpty);
    });

    test('lo que todavía espera subir sobre otra fila no se pisa', () async {
      await insertarEncargo(
        base,
        id: 'e1',
        clienteId: 'ana',
        creadoEn: marca,
        descripcion: 'Vestido',
      );
      await insertarPago(base, id: 'mio', encargoId: 'e1', centimos: 900);
      final actual = (await encargos.observar('e1').first)!;
      await encargos.editar(
        actual,
        descripcion: 'Rechazado',
        fechaEntregaAcordada: actual.fechaEntregaAcordada,
        ubicacion: '',
        notas: '',
      );
      // Un pago propio encolado después, todavía sin subir.
      await outbox.encolar(
        const OperacionNueva(
          tipo: 'crear_pago',
          metodo: 'POST',
          ruta: '/encargos/e1/pagos',
          entidadId: 'mio',
          encargoId: 'e1',
        ),
      );
      final apartada = await rechazar();
      backend.cuando('GET /encargos/e1', (_) => detalle());

      await descarte.descartar(apartada);

      expect((await base.select(base.encargos).getSingle()).descripcion, 'Vestido de noche');
      expect((await base.select(base.pagos).getSingle()).id, 'mio');
      expect([for (final op in await cola()) op.entidadId], ['mio']);
    });

    test('trabajo rechazado: sale, y el total se recalcula con lo que sigue sin subir', () async {
      await insertarEncargo(base, id: 'e1', clienteId: 'ana', creadoEn: marca);
      var siguiente = 0;
      final trabajos = RepositorioTrabajos(
        base: base,
        outbox: outbox,
        nuevoId: () => 't${++siguiente}',
      );
      await trabajos.agregarPersonalizado('e1', descripcion: 'Rechazado', precio: Monto.desde(50));
      await trabajos.agregarPersonalizado('e1', descripcion: 'Pendiente', precio: Monto.desde(20));
      final apartada = await rechazar();
      // El servidor no tiene ninguno de los dos: su total es 0.
      backend.cuando(
        'GET /encargos/e1',
        (_) => Respuesta(200, {
          ...detalle().cuerpo! as Map<String, Object?>,
          'precio_total': 0,
          'saldo_pendiente': 0,
        }),
      );

      await descarte.descartar(apartada);

      final filas = await base.select(base.trabajos).get();
      expect([for (final t in filas) t.descripcion], ['Pendiente']);
      final encargo = await base.select(base.encargos).getSingle();
      expect([encargo.precioTotal, encargo.saldoPendiente], [2000, 2000]);
      expect([for (final op in await cola()) op.entidadId], ['t2']);
    });
  });
}
