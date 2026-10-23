import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/features/encargos/presentation/hoja_cambiar_estado.dart';
import 'package:gestor_encargos/router/router.dart';
import 'package:gestor_encargos/router/rutas.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';

import '../../../helpers/encargos_prueba.dart';
import '../../../helpers/entorno_prueba.dart';

const marca = '2026-10-01T15:00:00.000Z';

/// "Avisar por WhatsApp" en el Detalle (S5c) visto por el usuario, con la app
/// completa, Drift en memoria y un abridor de enlaces falso.
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
    String estado = 'LISTO',
    int saldo = 0,
    String? telefono = '+51987654321',
  }) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
    await entorno.base
        .into(entorno.base.clientes)
        .insert(
          ClientesCompanion.insert(
            id: 'ana',
            creadoEn: marca,
            actualizadoEn: marca,
            nombre: 'Ana García',
            nombreBusqueda: 'ana garcia',
            telefono: Value(telefono),
          ),
        );
    await insertarEncargo(
      entorno.base,
      id: 'e1',
      clienteId: 'ana',
      numero: 47,
      estado: estado,
      creadoEn: marca,
      saldoCentimos: saldo,
      listo: estado == 'LISTO' || estado == 'ENTREGADO' ? '2026-10-20' : null,
    );
    unawaited(contenedor(tester).read(routerProvider).push(Rutas.encargo('e1')));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  final whatsapp = find.widgetWithText(FilledButton, 'WhatsApp');
  final cambiarEstado = find.widgetWithText(FilledButton, 'Cambiar estado');
  String? textoEnviado() => entorno.enlaces.abiertos.single.queryParameters['text'];

  probar('listo: abre wa.me con el número y el mensaje del Caso 12', (tester) async {
    await abrirDetalle(tester, saldo: 3000);

    expect(cambiarEstado, findsOneWidget, reason: 'lado a lado (wireframe)');
    await tocar(tester, whatsapp);

    final enlace = entorno.enlaces.abiertos.single;
    expect([enlace.host, enlace.path], ['wa.me', '/51987654321']);
    expect(
      textoEnviado(),
      'Hola Ana García, su encargo está listo para recoger. Saldo pendiente: S/ 30.00. '
      'Cualquier consulta, escríbame.',
    );
  });

  probar('entregado: solo WhatsApp, para cobrar lo fiado', (tester) async {
    await abrirDetalle(tester, estado: 'ENTREGADO', saldo: 2000);

    expect(cambiarEstado, findsNothing);
    await tocar(tester, whatsapp);

    expect(textoEnviado(), startsWith('Hola Ana García, le recuerdo que quedó un saldo pendiente'));
  });

  probar('al marcar Listo, el aviso trae "Avisar" con el mensaje de Listo (P3)', (tester) async {
    await abrirDetalle(tester, estado: 'EN_PROCESO');

    await tocar(tester, cambiarEstado);
    await tocar(
      tester,
      find.descendant(of: find.byType(HojaCambiarEstado), matching: find.text('Listo')),
    );
    expect(find.text('Ahora: Listo'), findsOneWidget);
    await tocar(tester, find.widgetWithText(SnackBarAction, 'Avisar'));

    expect(textoEnviado(), startsWith('Hola Ana García, su encargo está listo para recoger.'));
  });

  probar('otro estado distinto de Listo: el aviso no trae "Avisar"', (tester) async {
    await abrirDetalle(tester, estado: 'EN_PROCESO');

    await tocar(tester, cambiarEstado);
    await tocar(
      tester,
      find.descendant(of: find.byType(HojaCambiarEstado), matching: find.text('Pausado')),
    );

    expect(find.text('Ahora: Pausado'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Avisar'), findsNothing);
  });

  probar('sin teléfono: lo explica, se agrega y sigue a WhatsApp (P2)', (tester) async {
    await abrirDetalle(tester, telefono: null);

    await tocar(tester, whatsapp);
    expect(find.text('Ana García no tiene teléfono'), findsOneWidget);
    await tocar(tester, find.widgetWithText(TextButton, 'Agregar teléfono'));
    await tester.enterText(find.widgetWithText(TextField, 'Celular (opcional)'), '912345678');
    await tester.pump();
    await tocar(tester, find.widgetWithText(FilledButton, 'Guardar'));

    expect(entorno.enlaces.abiertos.single.path, '/51912345678');
    final guardado = await entorno.base.select(entorno.base.clientes).getSingle();
    expect(guardado.telefono, '+51912345678');
  });

  probar('sin teléfono, "Ahora no" no abre nada', (tester) async {
    await abrirDetalle(tester, telefono: null);

    await tocar(tester, whatsapp);
    await tocar(tester, find.widgetWithText(TextButton, 'Ahora no'));

    expect(entorno.enlaces.abiertos, isEmpty);
  });

  probar('si no se puede abrir, lo dice en lenguaje humano', (tester) async {
    entorno.enlaces.resultado = false;
    await abrirDetalle(tester);

    await tocar(tester, whatsapp);

    expect(find.text('No se pudo abrir WhatsApp.'), findsOneWidget);
  });

  probar('con letra al 200% los botones van uno sobre otro, sin desbordes', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await abrirDetalle(tester);

    expect(tester.getTopLeft(whatsapp).dy, greaterThan(tester.getTopLeft(cambiarEstado).dy));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
