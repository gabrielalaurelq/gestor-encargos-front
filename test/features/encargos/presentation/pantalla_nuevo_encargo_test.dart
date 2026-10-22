import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/features/clientes/application/clientes.dart';
import 'package:gestor_encargos/shared/domain/dia.dart';
import 'package:gestor_encargos/shared/domain/telefono.dart';
import 'package:gestor_encargos/shared/sync/numeracion.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/entorno_prueba.dart';

/// Crear Encargo visto por el usuario (PRD módulo 2, Caso 7), con la app
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

  Future<void> abrirApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> crearCliente(WidgetTester tester, String nombre) async {
    await contenedor(tester)
        .read(repositorioClientesProvider)
        .crear(nombre: nombre, telefono: Telefono.peruano('987654321'));
    await tester.pumpAndSettle();
  }

  /// Desde el (+) del Inicio: sin cliente elegido.
  Future<void> abrirDesdeInicio(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Nuevo encargo'));
    await tester.pumpAndSettle();
  }

  /// Desde la ficha de Ana: ya elegida.
  Future<void> abrirDesdeFicha(WidgetTester tester) async {
    await tester.tap(find.text('Clientes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Pérez'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo encargo'));
    await tester.pumpAndSettle();
  }

  /// `pageBack()` busca el tooltip "Back", pero la app está en español. La
  /// pantalla de arriba es la última en el árbol: las de abajo siguen ahí.
  Future<void> atras(WidgetTester tester) => tester.tap(find.byType(BackButton).last);

  Finder descripcion() => find.widgetWithText(TextField, '¿Qué hay que hacer?');

  Future<List<OperacionOutbox>> cola() => entorno.base.select(entorno.base.operacionesOutbox).get();

  probar('desde la ficha: el cliente viene elegido; guardar abre el detalle', (tester) async {
    await entorno.base.guardarMetadato(Numeracion.claveRangos, '[[15,100]]');
    await abrirApp(tester);
    await crearCliente(tester, 'Ana Pérez');
    await abrirDesdeFicha(tester);

    expect(find.widgetWithText(ListTile, 'Ana Pérez'), findsOneWidget);
    await tester.enterText(descripcion(), 'Basta de pantalón azul');
    await tester.tap(find.text('Mañana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar encargo'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Detalle del encargo'), findsOneWidget);
    expect(find.text('Encargo #15 creado'), findsOneWidget);
    final cuerpo = (await cola()).last.cuerpoJson!;
    expect(cuerpo['numero'], 15);
    expect(cuerpo['descripcion'], 'Basta de pantalón azul');
    expect(
      cuerpo['fecha_entrega_acordada'],
      isoDesdeDia(hoyDelNegocio().add(const Duration(days: 1))),
    );

    // "Atrás" no vuelve al formulario ya guardado: vuelve a la ficha.
    await atras(tester);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Ana Pérez'), findsOneWidget);
    expect(find.text('Basta de pantalón azul'), findsOneWidget, reason: 'ya está en su lista');
  });

  probar('sin número disponible se crea igual y lo dice sin número', (tester) async {
    await abrirApp(tester);
    await crearCliente(tester, 'Ana Pérez');
    await abrirDesdeFicha(tester);

    await tester.enterText(descripcion(), 'Cierre');
    await tester.tap(find.text('Hoy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar encargo'));
    await tester.pumpAndSettle();

    expect(find.text('Encargo creado'), findsOneWidget);
  });

  probar('sin nada: marca los tres campos y no guarda', (tester) async {
    await abrirApp(tester);
    await abrirDesdeInicio(tester);

    await tester.tap(find.text('Guardar encargo'));
    await tester.pumpAndSettle();

    expect(find.text('Elige el cliente.'), findsOneWidget);
    expect(find.text('Escribe qué hay que hacer.'), findsOneWidget);
    expect(find.text('Elige la fecha de entrega.'), findsOneWidget);
    expect(await cola(), isEmpty);
  });

  probar('elegir cliente: la misma búsqueda de la pestaña Clientes', (tester) async {
    await abrirApp(tester);
    await crearCliente(tester, 'María Núñez');
    await crearCliente(tester, 'Luis Rojas');
    await abrirDesdeInicio(tester);

    await tester.tap(find.text('Elegir cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Buscar por nombre o celular'), 'nunez');
    await tester.pumpAndSettle();
    expect(find.text('Luis Rojas'), findsNothing);
    await tester.tap(find.text('María Núñez'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'María Núñez'), findsOneWidget);
    expect(find.text('Cambiar'), findsOneWidget);
  });

  probar('cliente nuevo sin salir del flujo; sube antes que su encargo', (tester) async {
    await abrirApp(tester);
    await crearCliente(tester, 'Luis Rojas');
    await abrirDesdeInicio(tester);

    await tester.tap(find.text('Elegir cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar por nombre o celular'),
      'Rosa Quispe',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear cliente «Rosa Quispe»'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Rosa Quispe'), findsOneWidget, reason: 'ya elegida');
    await tester.enterText(descripcion(), 'Basta');
    await tester.tap(find.text('En 3 días'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar encargo'));
    await tester.pumpAndSettle();

    final rutas = [for (final op in await cola()) op.ruta];
    expect(rutas, ['/clientes', '/clientes', '/encargos'], reason: 'Luis, Rosa y el encargo');
  });

  probar('fecha ya pasada: avisa sin bloquear y "Guardar igual" la guarda', (tester) async {
    await abrirApp(tester);
    await crearCliente(tester, 'Ana Pérez');
    await abrirDesdeFicha(tester);
    await tester.enterText(descripcion(), 'Zapatos del cuaderno');

    await tester.tap(find.text('Otra fecha…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left)); // mes anterior
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    final ok = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    ).okButtonLabel;
    await tester.tap(find.text(ok));
    await tester.pumpAndSettle();

    expect(find.text('Esa fecha ya pasó. ¿Es correcta?'), findsOneWidget);
    await tester.tap(find.text('Guardar igual'));
    await tester.pumpAndSettle();

    final hoy = hoyDelNegocio();
    final mesAnterior = DateTime.utc(hoy.year, hoy.month - 1, 15);
    expect((await cola()).last.cuerpoJson!['fecha_entrega_acordada'], isoDesdeDia(mesAnterior));
  });

  group('salir sin guardar (Doc 6: error imposible)', () {
    probar('con algo escrito, pregunta antes de descartar', (tester) async {
      await abrirApp(tester);
      await abrirDesdeInicio(tester);
      await tester.enterText(descripcion(), 'Basta');
      await tester.pump();

      await atras(tester);
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar este encargo?'), findsOneWidget);
      await tester.tap(find.text('Seguir editando'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Nuevo encargo'), findsOneWidget);

      await atras(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Nuevo encargo'), findsNothing);
      expect(await cola(), isEmpty);
    });

    probar('vacío (aunque venga con cliente de la ficha), sale sin preguntar', (tester) async {
      await abrirApp(tester);
      await crearCliente(tester, 'Ana Pérez');
      await abrirDesdeFicha(tester);

      await atras(tester);
      await tester.pumpAndSettle();

      expect(find.text('¿Descartar este encargo?'), findsNothing);
      expect(find.widgetWithText(AppBar, 'Ana Pérez'), findsOneWidget);
    });
  });

  probar('todo lo tocable mide al menos 56dp y el texto tiene contraste (Doc 6)', (tester) async {
    await abrirApp(tester);
    await abrirDesdeInicio(tester);
    await tester.tap(find.text('Guardar encargo'));
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
