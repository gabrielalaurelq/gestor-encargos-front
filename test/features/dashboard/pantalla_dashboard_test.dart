import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/features/sesion/application/sesion.dart';
import 'package:gestor_encargos/shared/domain/dia.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/presentation/formato_fecha.dart';

import '../../helpers/encargos_prueba.dart';
import '../../helpers/entorno_prueba.dart';

const marca = '2026-10-01T15:00:00.000Z';

/// El Dashboard (S5a) visto por el usuario, con la app completa y Drift en
/// memoria. La pantalla usa el día real del negocio, así que las fechas de
/// los encargos se arman desde hoy.
void main() {
  late EntornoPrueba entorno;
  final hoy = hoyDelNegocio();
  String dia(int desdeHoy) => isoDesdeDia(hoy.add(Duration(days: desdeHoy)));

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

  Future<void> abrirApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cliente(String id, String nombre) => entorno.base
      .into(entorno.base.clientes)
      .insert(
        ClientesCompanion.insert(
          id: id,
          creadoEn: marca,
          actualizadoEn: marca,
          nombre: nombre,
          nombreBusqueda: nombre.toLowerCase(),
        ),
      );

  var siguiente = 0;
  Future<void> encargo(
    String estado, {
    required String entrega,
    String clienteId = 'rosa',
    String descripcion = 'Basta de pantalón',
    int saldo = 0,
    String? listo,
    int? numero,
  }) => insertarEncargo(
    entorno.base,
    id: 'e${++siguiente}',
    clienteId: clienteId,
    creadoEn: marca,
    numero: numero ?? siguiente,
    estado: estado,
    descripcion: descripcion,
    entregaAcordada: entrega,
    saldoCentimos: saldo,
    listo: listo,
  );

  /// El valor de un recuadro de arriba, buscado junto a su etiqueta.
  Finder recuadro(String etiqueta, String valor) => find.ancestor(
    of: find.text(etiqueta),
    matching: find.ancestor(of: find.text(valor), matching: find.byType(Card)),
  );

  Future<void> cargarDia() async {
    await cliente('rosa', 'Rosa Delgado');
    await cliente('ana', 'Ana García');
    await encargo('EN_PROCESO', entrega: dia(-1), saldo: 3000);
    await encargo('PAUSADO', entrega: dia(-3), descripcion: 'Cierre de casaca');
    await encargo(
      'LISTO',
      entrega: dia(0),
      clienteId: 'ana',
      descripcion: 'Vestido',
      listo: dia(-1),
    );
    await encargo('ENTREGADO', entrega: dia(-5), saldo: 2000, listo: dia(-5));
    await encargo('INGRESADO', entrega: dia(4));
  }

  probar('sin nada pendiente: mensaje amigable y el + a mano (Doc 6)', (tester) async {
    await abrirApp(tester);

    expect(find.text('Aún no tienes encargos pendientes. Toca + para crear uno.'), findsOneWidget);
    expect(find.byTooltip('Nuevo encargo'), findsOneWidget);
  });

  probar('cabecera: el nombre del negocio y la fecha de hoy', (tester) async {
    await entorno.base.guardarMetadato(claveNombreNegocio, 'Costurería Ana');
    await abrirApp(tester);

    expect(find.text('Costurería Ana'), findsOneWidget);
    expect(find.text('Hoy, ${formatearDiaLargo(hoy)}'), findsOneWidget);
  });

  probar('sin nombre guardado: "Inicio"', (tester) async {
    await abrirApp(tester);

    expect(find.widgetWithText(AppBar, 'Inicio'), findsOneWidget);
  });

  probar('los tres números: activos, entregas de hoy y lo que deben (P1, P2)', (tester) async {
    await abrirApp(tester);
    await cargarDia();
    await tester.pumpAndSettle();

    expect(recuadro('Encargos activos', '4'), findsOneWidget);
    expect(recuadro('Entregas hoy', '1'), findsOneWidget);
    expect(recuadro('Saldo pendiente', 'S/ 50.00'), findsOneWidget, reason: 'incluye el fiado');
  });

  probar('atrasados en rojo, del más antiguo, antes que las entregas de hoy', (tester) async {
    await abrirApp(tester);
    await cargarDia();
    await tester.pumpAndSettle();

    final casaca = find.text('Cierre de casaca · debía estar listo hace 3 días');
    final basta = find.text('Basta de pantalón · debía estar listo ayer');
    expect(casaca, findsOneWidget);
    expect(basta, findsOneWidget);
    double alto(Finder f) => tester.getTopLeft(f).dy;
    expect(alto(find.text('Atrasados')), lessThan(alto(casaca)));
    expect(alto(casaca), lessThan(alto(basta)));
    expect(alto(basta), lessThan(alto(find.text('Entregas de hoy'))));
    expect(find.text('Vestido'), findsOneWidget);
    expect(find.text('Ana García'), findsOneWidget);
  });

  probar('sin entregas para hoy lo dice', (tester) async {
    await abrirApp(tester);
    await cliente('rosa', 'Rosa Delgado');
    await encargo('EN_PROCESO', entrega: dia(2));
    await tester.pumpAndSettle();

    expect(find.text('Nada pendiente para hoy.'), findsOneWidget);
    expect(find.text('Atrasados'), findsNothing);
  });

  probar('un toque en un encargo abre su detalle (PRD 7)', (tester) async {
    await abrirApp(tester);
    await cliente('rosa', 'Rosa Delgado');
    await encargo('EN_PROCESO', entrega: dia(0), numero: 47);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rosa Delgado'));
    await tester.pumpAndSettle();

    expect(find.text('Encargo #47'), findsOneWidget);
  });

  probar('cumple 56dp y contraste, y aguanta letra al 200% (Doc 6)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await entorno.base.guardarMetadato(claveNombreNegocio, 'Costurería Ana');
    await abrirApp(tester);
    await cargarDia();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
