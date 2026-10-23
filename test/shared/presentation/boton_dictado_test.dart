import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/router/router.dart';
import 'package:gestor_encargos/router/rutas.dart';
import 'package:gestor_encargos/shared/infrastructure/dictado.dart';

import '../../helpers/encargos_prueba.dart';
import '../../helpers/entorno_prueba.dart';

/// El micrófono de los campos (S5d) visto por el usuario, con la app
/// completa y un dictado falso: la prueba decide qué "se oye".
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

  Future<void> ir(WidgetTester tester, String ruta) async {
    unawaited(contenedor(tester).read(routerProvider).push(ruta));
    await tester.pumpAndSettle();
  }

  Future<void> abrirApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  final descripcion = find.widgetWithText(TextField, '¿Qué hay que hacer?');
  final dictar = find.byTooltip('Dictar');
  String textoDe(WidgetTester tester, Finder campo) =>
      tester.widget<TextField>(campo).controller!.text;

  group('en Crear encargo', () {
    probar('lo dictado aparece mientras se habla, con mayúscula, sin guardar nada', (tester) async {
      await abrirApp(tester);
      await ir(tester, Rutas.nuevoEncargo);

      expect(dictar, findsOneWidget, reason: 'solo la descripción, no el cliente (P1)');
      await tocar(tester, dictar);
      expect(find.text('Escuchando…'), findsOneWidget);
      entorno.dictado.oir('basta de');
      await tester.pump();
      expect(textoDe(tester, descripcion), 'Basta de');
      entorno.dictado.oir('basta de pantalón azul');
      entorno.dictado.callar();
      await tester.pumpAndSettle();

      expect(textoDe(tester, descripcion), 'Basta de pantalón azul');
      expect(find.text('Escuchando…'), findsNothing);
      expect(dictar, findsOneWidget);
      expect(await entorno.base.select(entorno.base.encargos).get(), isEmpty);
    });

    probar('se agrega al final de lo ya escrito, nunca lo borra (P2)', (tester) async {
      await abrirApp(tester);
      await ir(tester, Rutas.nuevoEncargo);
      await tester.enterText(descripcion, 'Basta de pantalón ');

      await tocar(tester, dictar);
      entorno.dictado.oir('y cambiar el cierre');
      entorno.dictado.callar();
      await tester.pumpAndSettle();

      expect(textoDe(tester, descripcion), 'Basta de pantalón y cambiar el cierre');
    });

    probar('si no se oye nada, el campo queda igual', (tester) async {
      await abrirApp(tester);
      await ir(tester, Rutas.nuevoEncargo);
      await tester.enterText(descripcion, 'Vestido');

      await tocar(tester, dictar);
      entorno.dictado.callar();
      await tester.pumpAndSettle();

      expect(textoDe(tester, descripcion), 'Vestido');
    });

    probar('tocar otra vez deja de escuchar', (tester) async {
      await abrirApp(tester);
      await ir(tester, Rutas.nuevoEncargo);

      await tocar(tester, dictar);
      await tocar(tester, find.byTooltip('Dejar de dictar'));

      expect(entorno.dictado.escuchando, isFalse);
      expect(dictar, findsOneWidget);
    });

    for (final (preparacion, aviso) in [
      (PreparacionDictado.sinPermiso, 'Sin permiso para el micrófono. Puedes seguir escribiendo.'),
      (
        PreparacionDictado.noDisponible,
        'El dictado por voz no está disponible en este teléfono. Puedes seguir escribiendo.',
      ),
    ]) {
      probar('${preparacion.name}: lo explica y oculta el micrófono (P3)', (tester) async {
        entorno.dictado.preparacion = preparacion;
        await abrirApp(tester);
        await ir(tester, Rutas.nuevoEncargo);

        await tocar(tester, dictar);
        expect(find.text(aviso), findsOneWidget);
        await tocar(tester, find.widgetWithText(TextButton, 'Entendido'));

        expect(dictar, findsNothing);
        await tester.enterText(descripcion, 'Se sigue escribiendo');
        expect(textoDe(tester, descripcion), 'Se sigue escribiendo');
      });
    }

    probar('con letra al 200% escuchando, sin desbordes', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await abrirApp(tester);
      await ir(tester, Rutas.nuevoEncargo);

      await tocar(tester, dictar);

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });
  });

  probar('oculto en un campo, oculto en todos hasta reabrir la app', (tester) async {
    entorno.dictado.preparacion = PreparacionDictado.sinPermiso;
    await abrirApp(tester);
    await insertarEncargo(
      entorno.base,
      id: 'e1',
      clienteId: 'ana',
      creadoEn: '2026-10-01T15:00:00.000Z',
    );
    await ir(tester, Rutas.encargo('e1'));
    await tocar(tester, find.byTooltip('Editar encargo'));
    expect(dictar, findsNWidgets(2), reason: 'descripción y notas');

    await tocar(tester, dictar.first);
    await tocar(tester, find.widgetWithText(TextButton, 'Entendido'));

    expect(dictar, findsNothing);
  });

  probar('también en objetos y en trabajos personalizados', (tester) async {
    await abrirApp(tester);
    await insertarEncargo(
      entorno.base,
      id: 'e1',
      clienteId: 'ana',
      estado: 'EN_PROCESO',
      creadoEn: '2026-10-01T15:00:00.000Z',
    );
    await ir(tester, Rutas.encargo('e1'));

    final agregarObjeto = find.widgetWithText(OutlinedButton, 'Agregar objeto');
    await tester.ensureVisible(agregarObjeto);
    await tocar(tester, agregarObjeto);
    await tocar(tester, dictar);
    entorno.dictado.oir('pantalón azul');
    entorno.dictado.callar();
    await tester.pumpAndSettle();
    expect(textoDe(tester, find.widgetWithText(TextField, 'Descripción')), 'Pantalón azul');
    await tester.tapAt(const Offset(180, 40));
    await tester.pumpAndSettle();

    final agregarTrabajo = find.widgetWithText(OutlinedButton, 'Agregar trabajo');
    await tester.ensureVisible(agregarTrabajo);
    await tocar(tester, agregarTrabajo);
    expect(dictar, findsOneWidget, reason: 'sin catálogo abre en Personalizado');
  });
}
