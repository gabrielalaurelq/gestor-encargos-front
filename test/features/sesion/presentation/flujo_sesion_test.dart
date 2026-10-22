import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';

import '../../../helpers/adaptador_falso.dart';
import '../../../helpers/entorno_prueba.dart';

/// La sesión vista por el usuario: de la app recién instalada al Dashboard, y
/// de Ajustes de vuelta al login.
void main() {
  // Las bases se cierran fuera del tiempo simulado (ver `testWidgetsConBase`):
  // "Más" lee la base desde que muestra los cambios no guardados.
  final abiertos = <EntornoPrueba>[];
  tearDown(() async {
    for (final entorno in abiertos) {
      await entorno.cerrar();
    }
    abiertos.clear();
  });

  Future<EntornoPrueba> abrirApp(WidgetTester tester, EntornoPrueba entorno) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    abiertos.add(entorno);

    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
    return entorno;
  }

  Future<void> irAAjustes(WidgetTester tester) async {
    await tester.tap(find.text('Más'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
  }

  Future<void> confirmarCierre(WidgetTester tester) async {
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Cerrar sesión')),
    );
    await tester.pumpAndSettle();
  }

  testWidgetsConBase('sin sesión arranca en el login, sin la barra inferior', (tester) async {
    await abrirApp(tester, EntornoPrueba());

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgetsConBase('"Continuar con Google" lleva directo al Dashboard (Doc 6: sin tour)', (
    tester,
  ) async {
    final entorno = EntornoPrueba()..loginAceptado();
    await abrirApp(tester, entorno);

    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Inicio'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgetsConBase('sin red, explica que la primera vez hace falta internet', (tester) async {
    final entorno = EntornoPrueba()..backend.sinRed = true;
    await abrirApp(tester, entorno);

    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();

    expect(find.textContaining('La primera vez se necesita conexión'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget, reason: 'puede reintentar');
  });

  testWidgetsConBase('cerrar sesión desde Ajustes, con confirmación, vuelve al login', (
    tester,
  ) async {
    final entorno = EntornoPrueba.conSesion();
    entorno.backend.cuando('POST /auth/logout', (_) => const Respuesta(204));
    await abrirApp(tester, entorno);
    await irAAjustes(tester);

    await confirmarCierre(tester);

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(await entorno.tokens.leer(), isNull);
  });

  testWidgetsConBase('"Cancelar" en la confirmación no cierra nada', (tester) async {
    final entorno = EntornoPrueba.conSesion();
    await abrirApp(tester, entorno);
    await irAAjustes(tester);

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Ajustes'), findsOneWidget);
    expect(entorno.backend.peticiones, isEmpty);
  });

  testWidgetsConBase('con cambios sin enviar, explica por qué no cierra', (tester) async {
    final entorno = EntornoPrueba.conSesion()..pendientes = 2;
    await abrirApp(tester, entorno);
    await irAAjustes(tester);

    await confirmarCierre(tester);

    expect(find.textContaining('Tienes 2 cambios sin enviar'), findsOneWidget);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Ajustes'), findsOneWidget);
  });

  testWidgetsConBase('el login cumple las guías de área táctil y contraste, con el error visible', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await abrirApp(tester, EntornoPrueba()..backend.sinRed = true);
    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgetsConBase('el login aguanta la letra del sistema al 200% sin desbordes', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await abrirApp(tester, EntornoPrueba()..backend.sinRed = true);

    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgetsConBase('si la sesión expira en uso, vuelve al login', (tester) async {
    final entorno = EntornoPrueba.conSesion();
    entorno.backend.cuando('POST /auth/logout', (_) => Respuesta.error(401, 'TOKEN_EXPIRADO'));
    entorno.backend.cuando('POST /auth/refresh', (_) => Respuesta.error(401, 'SESION_INVALIDA'));
    await abrirApp(tester, entorno);
    await irAAjustes(tester);

    // El logout da 401 y el refresh también: el interceptor avisa la
    // expiración y la sesión termina de cerrarse en el teléfono.
    await confirmarCierre(tester);

    expect(find.text('Continuar con Google'), findsOneWidget);
  });
}
