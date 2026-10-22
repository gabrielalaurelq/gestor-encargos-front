import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/router/router.dart';
import 'package:gestor_encargos/router/rutas.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/infrastructure/http/error_api.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../helpers/adaptador_falso.dart';
import '../../helpers/encargos_prueba.dart';
import '../../helpers/entorno_prueba.dart';

const marca = '2026-10-22T15:00:00.000Z';

/// "Cambios no guardados" (Doc 7 v1.2; decisión del usuario: solo
/// "Descartar"), con la app completa, Drift en memoria y el backend falso.
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

  Future<List<OperacionOutbox>> cola() => entorno.base.select(entorno.base.operacionesOutbox).get();

  /// Ana con el encargo #47, y una edición suya que el servidor rechazó.
  Future<void> conRechazo() async {
    final base = entorno.base;
    await base
        .into(base.clientes)
        .insert(
          ClientesCompanion.insert(
            id: 'ana',
            creadoEn: marca,
            actualizadoEn: marca,
            nombre: 'Ana García',
            nombreBusqueda: 'ana garcia',
          ),
        );
    await insertarEncargo(
      base,
      id: 'e1',
      clienteId: 'ana',
      numero: 47,
      creadoEn: marca,
      descripcion: 'Descripción rechazada',
    );
    final outbox = Outbox(base);
    final id = await outbox.encolar(
      const OperacionNueva(
        tipo: 'editar_encargo',
        metodo: 'PATCH',
        ruta: '/encargos/e1',
        cuerpo: {'descripcion': 'Descripción rechazada'},
        entidadId: 'e1',
        encargoId: 'e1',
      ),
    );
    await outbox.apartar(
      id,
      const ErrorRechazado(
        codigo: 'TRANSICION_INVALIDA',
        mensaje: 'El encargo ya fue entregado.',
        status: 422,
      ),
    );
    await outbox.cerrar();
    entorno.backend.cuando(
      'GET /encargos/e1',
      (_) => const Respuesta(200, {
        'id': 'e1',
        'cliente_id': 'ana',
        'numero': 47,
        'descripcion': 'Vestido de noche',
        'estado': 'ENTREGADO',
        'precio_total': 0,
        'descuento': 0,
        'saldo_pendiente': 0,
        'fecha_entrega_prometida': '2026-10-24',
        'fecha_entrega_acordada': '2026-10-24',
        'fecha_listo': '2026-10-21',
        'fecha_entrega_real': '2026-10-22',
        'ubicacion_fisica': null,
        'notas_generales': null,
        'creado_en': marca,
        'actualizado_en': marca,
        'objetos': <Object>[],
        'trabajos': <Object>[],
        'pagos': <Object>[],
        'notas': <Object>[],
        'fotos': <Object>[],
      }),
    );
  }

  Future<void> abrirApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> abrirMas(WidgetTester tester) async {
    await tester.tap(find.text('Más'));
    await tester.pumpAndSettle();
  }

  Future<void> abrirCambios(WidgetTester tester) async {
    await abrirMas(tester);
    await tester.tap(find.text('Cambios no guardados (1)'));
    await tester.pumpAndSettle();
  }

  Future<void> descartar(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar este cambio?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Descartar'));
    await tester.pumpAndSettle();
  }

  probar('sin rechazos, "Más" no muestra nada (nunca un banner)', (tester) async {
    await abrirApp(tester);
    await abrirMas(tester);

    expect(find.textContaining('Cambios no guardados'), findsNothing);
  });

  probar('con un rechazo: aparece en "Más" con qué se intentó y por qué', (tester) async {
    await conRechazo();
    await abrirApp(tester);
    await abrirCambios(tester);

    expect(find.text('Editar encargo · #47 · Ana García'), findsOneWidget);
    expect(find.text('El encargo ya fue entregado.'), findsOneWidget);
  });

  probar('"Descartar" confirma, vuelve a la versión del servidor y vacía la lista', (tester) async {
    await conRechazo();
    await abrirApp(tester);
    await abrirCambios(tester);

    await descartar(tester);

    expect(find.text('Cambio descartado'), findsOneWidget);
    expect(find.text('Todo está guardado.'), findsOneWidget);
    expect(await cola(), isEmpty);
    final fila = await entorno.base.select(entorno.base.encargos).getSingle();
    expect([fila.descripcion, fila.estado], ['Vestido de noche', 'ENTREGADO']);

    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Cambios no guardados'), findsNothing);
  });

  probar('sin conexión lo explica y no toca nada', (tester) async {
    await conRechazo();
    entorno.backend.sinRed = true;
    await abrirApp(tester);
    await abrirCambios(tester);

    await descartar(tester);

    expect(find.text('Necesitas conexión para descartar.'), findsOneWidget);
    expect(find.text('Editar encargo · #47 · Ana García'), findsOneWidget);
    expect(
      (await entorno.base.select(entorno.base.encargos).getSingle()).descripcion,
      'Descripción rechazada',
    );
  });

  probar('el detalle del encargo lo avisa y lleva a la lista', (tester) async {
    await conRechazo();
    await abrirApp(tester);
    unawaited(contenedor(tester).read(routerProvider).push(Rutas.encargo('e1')));
    await tester.pumpAndSettle();

    expect(find.text('Un cambio de este encargo no se guardó.'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Cambios no guardados'), findsOneWidget);
    await tester.tap(find.text('Ver encargo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Encargo #47'), findsOneWidget);
  });

  probar('todo lo tocable mide al menos 56dp y el texto tiene contraste (Doc 6)', (tester) async {
    await conRechazo();
    await abrirApp(tester);
    await abrirCambios(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
