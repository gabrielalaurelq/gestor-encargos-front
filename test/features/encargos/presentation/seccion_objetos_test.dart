import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/features/encargos/presentation/seccion_objetos.dart';
import 'package:gestor_encargos/router/router.dart';
import 'package:gestor_encargos/router/rutas.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/encargos_prueba.dart';
import '../../../helpers/entorno_prueba.dart';

const marca = '2026-10-01T15:00:00.000Z';

/// La sección Objetos recibidos del Detalle (S3d1) vista por el usuario, con
/// la app completa y Drift en memoria.
void main() {
  late EntornoPrueba entorno;

  setUp(() => entorno = EntornoPrueba.conSesion());
  tearDown(() => entorno.cerrar());

  void probar(String descripcion, Future<void> Function(WidgetTester) cuerpo) {
    testWidgetsConBase(descripcion, (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await cuerpo(tester);
    });
  }

  ProviderContainer contenedor(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

  Future<void> objeto(String id, String descripcion) => entorno.base
      .into(entorno.base.objetosRecibidos)
      .insert(
        ObjetosRecibidosCompanion.insert(
          id: id,
          creadoEn: marca,
          actualizadoEn: marca,
          encargoId: 'e1',
          descripcion: descripcion,
        ),
      );

  Future<void> trabajo(String id, {String? objeto}) => entorno.base
      .into(entorno.base.trabajos)
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

  Future<void> abrirDetalle(WidgetTester tester, {String estado = 'EN_PROCESO'}) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
    await insertarEncargo(
      entorno.base,
      id: 'e1',
      clienteId: 'ana',
      numero: 47,
      estado: estado,
      creadoEn: marca,
    );
    unawaited(contenedor(tester).read(routerProvider).push(Rutas.encargo('e1')));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<List<OperacionOutbox>> deObjetos() async => [
    for (final op in await entorno.base.select(entorno.base.operacionesOutbox).get())
      if (op.tipo.endsWith('_objeto')) op,
  ];

  /// Un texto dentro de esta sección (con vínculos, Trabajos repite el
  /// objeto como subtítulo).
  Finder enObjetos(String texto) =>
      find.descendant(of: find.byType(SeccionObjetos), matching: find.text(texto));

  final agregarObjeto = find.widgetWithText(OutlinedButton, 'Agregar objeto');
  final descripcion = find.widgetWithText(TextField, 'Descripción');

  probar('va antes que Trabajos y, sin objetos, no es un error (Caso 3)', (tester) async {
    await abrirDetalle(tester);

    expect(find.text('Ningún objeto registrado.'), findsOneWidget);
    expect(agregarObjeto, findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Objetos recibidos')).dy,
      lessThan(tester.getTopLeft(find.text('Trabajos', skipOffstage: false)).dy),
    );
  });

  probar('agregar un objeto: aparece en la lista, sin trabajos', (tester) async {
    await abrirDetalle(tester);
    await tocar(tester, agregarObjeto);

    await tester.enterText(descripcion, 'Pantalón azul');
    await tester.pump();
    await tocar(tester, find.widgetWithText(FilledButton, 'Agregar'));

    expect(find.text('Objeto agregado'), findsOneWidget);
    expect(find.text('Pantalón azul'), findsOneWidget);
    expect(find.text('sin trabajos'), findsOneWidget);
    expect((await deObjetos()).single.cuerpoJson!['descripcion'], 'Pantalón azul');
  });

  probar('sin descripción no agrega', (tester) async {
    await abrirDetalle(tester);
    await tocar(tester, agregarObjeto);

    await tocar(tester, find.widgetWithText(FilledButton, 'Agregar'));

    expect(find.text('Escribe qué dejó el cliente.'), findsOneWidget);
    expect(await deObjetos(), isEmpty);
  });

  probar('cuenta sus trabajos; tocarlo deja editar la descripción', (tester) async {
    await objeto('o1', 'Pantalón');
    await trabajo('t1', objeto: 'o1');
    await trabajo('t2', objeto: 'o1');
    await abrirDetalle(tester);

    expect(find.text('2 trabajos'), findsOneWidget);
    await tocar(tester, enObjetos('Pantalón'));
    expect(find.text('Editar objeto'), findsOneWidget);
    await tester.enterText(descripcion, 'Pantalón de vestir');
    await tester.pump();
    await tocar(tester, find.widgetWithText(FilledButton, 'Guardar'));

    expect(find.text('Cambios guardados'), findsOneWidget);
    expect(enObjetos('Pantalón de vestir'), findsOneWidget);
    expect((await deObjetos()).single.metodo, 'PATCH');
  });

  probar('eliminar avisa que sus trabajos se quedan, y se quedan', (tester) async {
    await objeto('o1', 'Pantalón');
    await trabajo('t1', objeto: 'o1');
    await trabajo('t2', objeto: 'o1');
    await abrirDetalle(tester);

    await tocar(tester, enObjetos('Pantalón'));
    await tocar(tester, find.widgetWithText(OutlinedButton, 'Eliminar objeto'));
    expect(
      find.text('"Pantalón" sale del encargo. Sus 2 trabajos se quedan, sin objeto.'),
      findsOneWidget,
    );
    await tocar(tester, find.widgetWithText(TextButton, 'Eliminar'));

    expect(find.text('Objeto eliminado'), findsOneWidget);
    expect(find.text('Ningún objeto registrado.'), findsOneWidget);
    final trabajos = await entorno.base.select(entorno.base.trabajos).get();
    expect([for (final t in trabajos) t.objetoRecibidoId], [null, null]);
    expect((await deObjetos()).single.metodo, 'DELETE');
  });

  probar('entregado: los objetos se ven pero no se cambian', (tester) async {
    await objeto('o1', 'Pantalón');
    await abrirDetalle(tester, estado: 'ENTREGADO');

    expect(find.text('Ya fue entregado: los objetos no se cambian.'), findsOneWidget);
    expect(agregarObjeto, findsNothing);
    await tocar(tester, enObjetos('Pantalón'));
    expect(find.text('Editar objeto'), findsNothing);
  });
}
