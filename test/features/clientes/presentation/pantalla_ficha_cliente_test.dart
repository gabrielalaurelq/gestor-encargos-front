import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/features/clientes/application/clientes.dart';
import 'package:gestor_encargos/features/clientes/domain/cliente.dart';
import 'package:gestor_encargos/router/router.dart';
import 'package:gestor_encargos/router/rutas.dart';
import 'package:gestor_encargos/shared/domain/telefono.dart';

import '../../../helpers/encargos_prueba.dart';
import '../../../helpers/entorno_prueba.dart';

/// La Ficha de Cliente vista por el usuario (PRD módulos 1 y 18), con la app
/// completa y Drift en memoria. Los encargos se escriben directo en la base,
/// como si hubieran bajado del servidor: crearlos llega en el Sprint 2.
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

  /// Abre la app, crea a Ana y entra a su ficha desde la pestaña Clientes.
  Future<Cliente> abrirFichaDeAna(
    WidgetTester tester, {
    Future<void> Function(String id)? antes,
  }) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
    final ana = await contenedor(tester)
        .read(repositorioClientesProvider)
        .crear(nombre: 'Ana Pérez', telefono: Telefono.peruano('987654321'));
    await antes?.call(ana.id);
    await tester.tap(find.text('Clientes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Pérez'));
    await tester.pumpAndSettle();
    return ana;
  }

  Future<void> conHistorial(String anaId) async {
    final base = entorno.base;
    await insertarEncargo(
      base,
      id: 'viejo',
      clienteId: anaId,
      numero: 9,
      descripcion: 'Zapatos marrones',
      estado: 'ENTREGADO',
      creadoEn: '2026-09-02T15:00:00.000Z',
      entregaAcordada: '2026-09-10',
      entregaReal: '2026-09-12',
    );
    await insertarEncargo(
      base,
      id: 'reciente',
      clienteId: anaId,
      numero: 14,
      descripcion: 'Basta de pantalón azul',
      estado: 'LISTO',
      saldoCentimos: 2000,
      creadoEn: '2026-10-20T15:00:00.000Z',
      entregaAcordada: '2026-10-23',
    );
    await insertarEncargo(
      base,
      id: 'cancelado',
      clienteId: anaId,
      descripcion: 'Cierre de casaca',
      estado: 'CANCELADO',
      saldoCentimos: 1500,
      creadoEn: '2026-10-01T15:00:00.000Z',
    );
    await insertarPago(base, id: 'p1', encargoId: 'viejo', centimos: 18000);
    await insertarPago(base, id: 'p2', encargoId: 'reciente', centimos: 3000);
    await insertarPago(base, id: 'p3', encargoId: 'cancelado', centimos: 2000);
  }

  probar('datos del cliente y, sin encargos, lo dice en vez de mostrar ceros', (tester) async {
    await abrirFichaDeAna(tester);

    expect(find.widgetWithText(AppBar, 'Ana Pérez'), findsOneWidget);
    expect(find.text('987 654 321'), findsOneWidget);
    expect(find.text('Aún no tiene encargos.'), findsOneWidget);
    expect(find.textContaining('S/ 0.00'), findsNothing);
  });

  probar('resumen: todos los encargos y todo lo pagado, también de cancelados (PRD 18)', (
    tester,
  ) async {
    await abrirFichaDeAna(tester, antes: conHistorial);

    expect(find.text('3 encargos · S/ 230.00 pagado'), findsOneWidget);
    expect(find.text('Última visita: 20 oct 2026'), findsOneWidget);
  });

  probar('encargos del más reciente al más antiguo, con número, estado y fechas', (tester) async {
    await abrirFichaDeAna(tester, antes: conHistorial);

    final orden = [
      for (final d in ['Basta de pantalón azul', 'Cierre de casaca', 'Zapatos marrones'])
        tester.getTopLeft(find.text(d)).dy,
    ];
    expect(orden, orderedEquals([...orden]..sort()));
    expect(find.text('#14 · Entrega: vie 23 oct\nDebe S/ 20.00'), findsOneWidget);
    expect(find.text('#9 · Entregado el 12 sep 2026'), findsOneWidget);
    expect(find.text('Sin número aún'), findsOneWidget, reason: 'cancelado: ni fecha ni deuda');
    expect(find.text('Listo'), findsOneWidget);
    expect(find.text('Entregado'), findsOneWidget);
    expect(find.text('Cancelado'), findsOneWidget);
  });

  probar('un pago que llega con la ficha abierta actualiza el resumen solo', (tester) async {
    await abrirFichaDeAna(tester, antes: conHistorial);

    await insertarPago(entorno.base, id: 'p4', encargoId: 'reciente', centimos: 2000);
    await tester.pumpAndSettle();

    expect(find.text('3 encargos · S/ 250.00 pagado'), findsOneWidget);
  });

  probar('tocar un encargo abre su detalle', (tester) async {
    await abrirFichaDeAna(tester, antes: conHistorial);

    await tester.tap(find.text('Basta de pantalón azul'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Encargo #14'), findsOneWidget);
  });

  probar('"Nuevo encargo" abre Crear Encargo con este cliente ya elegido', (tester) async {
    final ana = await abrirFichaDeAna(tester);

    await tester.tap(find.text('Nuevo encargo'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Nuevo encargo'), findsOneWidget);
    final estado = GoRouterState.of(tester.element(find.widgetWithText(AppBar, 'Nuevo encargo')));
    expect(estado.uri.queryParameters['cliente'], ana.id);
  });

  probar('editar: la misma hoja del alta; al guardar, la ficha se actualiza', (tester) async {
    await abrirFichaDeAna(tester);

    await tester.tap(find.byTooltip('Editar cliente'));
    await tester.pumpAndSettle();
    expect(find.text('Editar cliente'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Ana María Pérez');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Ana María Pérez'), findsOneWidget);
    expect(find.text('Cambios guardados'), findsOneWidget);
  });

  probar('un enlace a un cliente que no está en el teléfono no rompe', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();

    unawaited(contenedor(tester).read(routerProvider).push(Rutas.cliente('no-existe')));
    await tester.pumpAndSettle();

    expect(find.text('Este cliente no existe.'), findsOneWidget);
  });

  probar('todo lo tocable mide al menos 56dp y el texto tiene contraste (Doc 6)', (tester) async {
    await abrirFichaDeAna(tester, antes: conHistorial);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
