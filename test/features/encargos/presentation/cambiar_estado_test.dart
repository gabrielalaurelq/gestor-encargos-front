import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/features/encargos/presentation/hoja_cambiar_estado.dart';
import 'package:gestor_encargos/router/router.dart';
import 'package:gestor_encargos/router/rutas.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/encargos_prueba.dart';
import '../../../helpers/entorno_prueba.dart';

const marca = '2026-10-01T15:00:00.000Z';

/// "Cambiar estado" en el Detalle (S4b) vista por el usuario, con la app
/// completa y Drift en memoria.
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

  Future<void> abrirDetalle(
    WidgetTester tester, {
    String estado = 'EN_PROCESO',
    int saldoCentimos = 0,
    String? listo,
  }) async {
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
      precioCentimos: saldoCentimos,
      saldoCentimos: saldoCentimos,
      listo: listo,
    );
    unawaited(contenedor(tester).read(routerProvider).push(Rutas.encargo('e1')));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  final botonCambiar = find.widgetWithText(FilledButton, 'Cambiar estado');

  /// Una opción de la hoja (el Detalle también muestra el estado actual).
  Finder opcion(String etiqueta) =>
      find.descendant(of: find.byType(HojaCambiarEstado), matching: find.text(etiqueta));

  List<String> opciones(WidgetTester tester) => [
    for (final tile in tester.widgetList<ListTile>(
      find.descendant(of: find.byType(HojaCambiarEstado), matching: find.byType(ListTile)),
    ))
      (tile.title! as Text).data!,
  ];

  Future<List<OperacionOutbox>> deEstado() async => [
    for (final op in await entorno.base.select(entorno.base.operacionesOutbox).get())
      if (op.tipo == 'cambiar_estado') op,
  ];

  Future<String> estadoGuardado() async =>
      (await entorno.base.select(entorno.base.encargos).getSingle()).estado;

  probar('en proceso → listo: un toque, sin confirmar, y avisa abajo', (tester) async {
    await abrirDetalle(tester);

    await tocar(tester, botonCambiar);
    expect(find.text('Ahora: En proceso'), findsOneWidget);
    expect(opciones(tester), ['Listo', 'Entregado', 'Pausado', 'Cancelado']);
    expect(find.text('Siguiente'), findsOneWidget);
    await tocar(tester, opcion('Listo'));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Ahora: Listo'), findsOneWidget, reason: 'SnackBar');
    expect(await estadoGuardado(), 'LISTO');
    expect((await deEstado()).single.cuerpoJson!['estado'], 'LISTO');
  });

  probar('desde listo no se ofrece volver a en proceso (decisión del usuario)', (tester) async {
    await abrirDetalle(tester, estado: 'LISTO', listo: '2026-10-20');

    await tocar(tester, botonCambiar);

    expect(opciones(tester), ['Entregado', 'Pausado', 'Cancelado']);
  });

  probar('entregar con saldo pregunta antes; "Volver" no cambia nada', (tester) async {
    await abrirDetalle(tester, estado: 'LISTO', saldoCentimos: 3000, listo: '2026-10-20');

    await tocar(tester, botonCambiar);
    await tocar(tester, opcion('Entregado'));
    expect(find.text('¿Entregar igual?'), findsOneWidget);
    expect(
      find.text('Queda S/ 30.00 por cobrar. Una vez entregado, ya no cambia de estado.'),
      findsOneWidget,
    );
    await tocar(tester, find.widgetWithText(TextButton, 'Volver'));
    expect(await estadoGuardado(), 'LISTO');
    expect(await deEstado(), isEmpty);

    await tocar(tester, opcion('Entregado'));
    await tocar(tester, find.widgetWithText(TextButton, 'Entregar igual'));

    expect(find.text('Ahora: Entregado'), findsOneWidget);
    expect(await estadoGuardado(), 'ENTREGADO');
    expect(botonCambiar, findsNothing, reason: 'entregado es terminal');
  });

  probar('entregar sin saldo igual confirma, porque no se deshace', (tester) async {
    await abrirDetalle(tester);

    await tocar(tester, botonCambiar);
    await tocar(tester, opcion('Entregado'));

    expect(find.text('¿Marcar como entregado?'), findsOneWidget);
    expect(find.textContaining('por cobrar'), findsNothing);
    await tocar(tester, find.widgetWithText(TextButton, 'Entregar'));
    expect(await estadoGuardado(), 'ENTREGADO');
  });

  probar('cancelar confirma, cierra las secciones y se puede reactivar', (tester) async {
    await abrirDetalle(tester);

    await tocar(tester, botonCambiar);
    await tocar(tester, opcion('Cancelado'));
    expect(find.text('¿Cancelar este encargo?'), findsOneWidget);
    await tocar(tester, find.widgetWithText(TextButton, 'Cancelar encargo'));
    expect(await estadoGuardado(), 'CANCELADO');
    await tester.scrollUntilVisible(
      find.text('Está cancelado: los trabajos no se cambian.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tocar(tester, botonCambiar);
    expect(opciones(tester), ['Ingresado', 'En proceso', 'Listo', 'Pausado']);
    expect(find.text('Siguiente'), findsNothing, reason: 'el anterior no se guarda (opción a)');
    await tocar(tester, opcion('En proceso'));

    expect(await estadoGuardado(), 'EN_PROCESO');
    expect(
      [for (final op in await deEstado()) op.cuerpoJson!['estado']],
      ['CANCELADO', 'EN_PROCESO'],
    );
  });

  probar('entregado: no hay botón', (tester) async {
    await abrirDetalle(tester, estado: 'ENTREGADO', listo: '2026-10-20');

    expect(botonCambiar, findsNothing);
  });

  probar('el botón y la hoja cumplen 56dp y contraste (Doc 6)', (tester) async {
    await abrirDetalle(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await tocar(tester, botonCambiar);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
