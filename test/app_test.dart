import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/shared/presentation/tema/tema.dart';

import 'helpers/entorno_prueba.dart';

/// Navegación del Doc 7 (Bloque 2) y reglas de accesibilidad del Doc 6, con
/// una sesión ya iniciada (el flujo de sesión está en `flujo_sesion_test`).
void main() {
  late EntornoPrueba entorno;

  setUp(() => entorno = EntornoPrueba.conSesion());
  tearDown(() => entorno.cerrar());

  Future<void> abrirApp(WidgetTester tester, {double escalaTexto = 1}) async {
    // Teléfono típico del público objetivo: 360x780 dp.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = escalaTexto;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
  }

  testWidgetsConBase('arranca en Inicio, con los 4 destinos del Doc 6', (tester) async {
    await abrirApp(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final destino in ['Inicio', 'Clientes', 'Calendario', 'Más']) {
      expect(
        find.descendant(of: find.byType(NavigationBar), matching: find.text(destino)),
        findsOneWidget,
      );
    }
    expect(find.widgetWithText(AppBar, 'Inicio'), findsOneWidget);
  });

  testWidgetsConBase('cambia de pestaña al tocar la barra', (tester) async {
    await abrirApp(tester);

    await tester.tap(find.text('Clientes'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Clientes'), findsOneWidget);
  });

  testWidgetsConBase('"Más" lleva a sus 4 opciones y abre una dentro del shell', (tester) async {
    await abrirApp(tester);

    await tester.tap(find.text('Más'));
    await tester.pumpAndSettle();
    for (final opcion in ['Balance de carga', 'Caja diaria', 'Catálogo de servicios', 'Ajustes']) {
      expect(find.text(opcion), findsOneWidget);
    }

    await tester.tap(find.text('Caja diaria'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Caja diaria'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'sigue dentro del shell');
  });

  testWidgetsConBase('"Nuevo encargo" se abre a pantalla completa, sin barra inferior', (
    tester,
  ) async {
    await abrirApp(tester);

    await tester.tap(find.byTooltip('Nuevo encargo'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Nuevo encargo'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgetsConBase('todo lo tocable mide al menos 56dp (Doc 6)', (tester) async {
    await abrirApp(tester);
    await tester.tap(find.text('Más'));
    await tester.pumpAndSettle();

    final tocables = [
      ...tester.widgetList(find.byType(ListTile)).map((w) => find.byWidget(w)),
      ...tester.widgetList(find.byType(NavigationDestination)).map((w) => find.byWidget(w)),
    ];
    expect(tocables, isNotEmpty);
    for (final tocable in tocables) {
      final tamano = tester.getSize(tocable);
      expect(tamano.height, greaterThanOrEqualTo(Medidas.toqueMinimo));
      expect(tamano.width, greaterThanOrEqualTo(Medidas.toqueMinimo));
    }
  });

  testWidgetsConBase('cumple las guías de Flutter de área táctil y contraste', (tester) async {
    final handle = tester.ensureSemantics();
    await abrirApp(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgetsConBase('respeta la letra grande del sistema sin desbordes (200%)', (tester) async {
    await abrirApp(tester, escalaTexto: 2);

    await tester.tap(find.text('Más'));
    await tester.pumpAndSettle();

    // Un desborde de layout se reporta como excepción del framework.
    expect(tester.takeException(), isNull);
  });
}
