import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/features/clientes/application/clientes.dart';
import 'package:gestor_encargos/router/router.dart';
import 'package:gestor_encargos/router/rutas.dart';
import 'package:gestor_encargos/shared/domain/dia.dart';
import 'package:gestor_encargos/shared/domain/telefono.dart';
import 'package:gestor_encargos/shared/presentation/formato_fecha.dart';
import 'package:gestor_encargos/shared/presentation/tema/colores.dart';

import '../../../helpers/encargos_prueba.dart';
import '../../../helpers/entorno_prueba.dart';

/// El Detalle de Encargo (cabecera, S2b) visto por el usuario, con la app
/// completa y Drift en memoria. Los encargos se escriben directo en la base,
/// como si hubieran bajado del servidor.
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

  final hoy = hoyDelNegocio();
  String iso(int dias) => isoDesdeDia(hoy.add(Duration(days: dias)));
  String dia(int dias) {
    final fecha = hoy.add(Duration(days: dias));
    return formatearDia(fecha, conDiaSemana: true, conAnio: fecha.year != hoy.year);
  }

  ProviderContainer contenedor(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

  /// Abre la app con Ana y un encargo suyo, y entra a su detalle.
  Future<void> abrirDetalle(
    WidgetTester tester, {
    int? numero = 47,
    String estado = 'EN_PROCESO',
    int saldoCentimos = 10000,
    int precioCentimos = 30000,
    int descuentoCentimos = 0,
    int entregaEnDias = 2,
    int? prometidaEnDias,
    int? listoEnDias,
    String? ubicacion = 'Cajón 3',
    String? notas,
  }) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
    final ana = await contenedor(tester)
        .read(repositorioClientesProvider)
        .crear(nombre: 'Ana García', telefono: Telefono.peruano('987654321'));
    await insertarEncargo(
      entorno.base,
      id: 'e1',
      clienteId: ana.id,
      numero: numero,
      descripcion: 'Vestido de noche',
      estado: estado,
      creadoEn: '2026-10-01T15:00:00.000Z',
      precioCentimos: precioCentimos,
      saldoCentimos: saldoCentimos,
      descuentoCentimos: descuentoCentimos,
      entregaAcordada: iso(entregaEnDias),
      entregaPrometida: prometidaEnDias == null ? null : iso(prometidaEnDias),
      listo: listoEnDias == null ? null : iso(listoEnDias),
      ubicacion: ubicacion,
      notas: notas,
    );
    unawaited(contenedor(tester).read(routerProvider).push(Rutas.encargo('e1')));
    await tester.pumpAndSettle();
  }

  Color? colorDe(WidgetTester tester, String texto) =>
      tester.widget<Text>(find.text(texto)).style?.color;

  probar('cabecera como el wireframe: número, estado, cliente, entrega, ubicación, montos', (
    tester,
  ) async {
    await abrirDetalle(tester);

    expect(find.widgetWithText(AppBar, 'Encargo #47'), findsOneWidget);
    expect(find.text('En proceso'), findsOneWidget);
    expect(find.text('Ana García'), findsOneWidget);
    expect(find.text('987 654 321'), findsOneWidget);
    expect(find.text('Vestido de noche'), findsOneWidget);
    expect(find.text(dia(2)), findsOneWidget);
    expect(find.text('Cajón 3'), findsOneWidget);
    expect(find.text('S/ 300.00'), findsOneWidget);
    expect(find.text('S/ 100.00'), findsOneWidget);
    expect(colorDe(tester, 'S/ 100.00'), Colores.rojo, reason: 'Doc 6: saldo > 0 en rojo');
    expect(find.text('Atrasado'), findsNothing);
    expect(find.text('Descuento'), findsNothing, reason: 'solo si hay');
  });

  probar('sin número, sin ubicación y saldo en cero: lo dice sin alarmar', (tester) async {
    await abrirDetalle(tester, numero: null, ubicacion: null, saldoCentimos: 0, precioCentimos: 0);

    expect(find.widgetWithText(AppBar, 'Encargo · sin número aún'), findsOneWidget);
    expect(find.text('Sin ubicación'), findsOneWidget);
    // Total y saldo valen S/ 0.00; ninguno en rojo.
    for (final texto in tester.widgetList<Text>(find.text('S/ 0.00'))) {
      expect(texto.style?.color, isNot(Colores.rojo));
    }
  });

  group('atrasado (Doc 2 regla 6; decisión del usuario)', () {
    probar('fecha pasada y sin "listo": en rojo con "Atrasado"', (tester) async {
      await abrirDetalle(tester, entregaEnDias: -3);

      expect(find.text('Atrasado'), findsOneWidget);
      expect(colorDe(tester, dia(-3)), Colores.rojo);
    });

    probar('ya listo: no está atrasado y muestra cuándo quedó listo', (tester) async {
      await abrirDetalle(tester, estado: 'LISTO', entregaEnDias: -3, listoEnDias: -1);

      expect(find.text('Atrasado'), findsNothing);
      expect(find.text('Listo el'), findsOneWidget);
      expect(find.text(dia(-1)), findsOneWidget);
    });

    probar('cancelado: no se marca aunque la fecha haya pasado', (tester) async {
      await abrirDetalle(tester, estado: 'CANCELADO', entregaEnDias: -3);

      expect(find.text('Atrasado'), findsNothing);
    });
  });

  probar('reprogramado: muestra la primera promesa', (tester) async {
    await abrirDetalle(tester, entregaEnDias: 5, prometidaEnDias: 2);

    expect(find.text('Prometido: ${dia(2)}'), findsOneWidget);
  });

  probar('saldo a favor del cliente y descuento', (tester) async {
    await abrirDetalle(tester, saldoCentimos: -2000, descuentoCentimos: 300);

    expect(find.text('A favor del cliente'), findsOneWidget);
    expect(find.text('S/ 20.00'), findsOneWidget);
    expect(find.text('Descuento'), findsOneWidget);
    expect(find.text('S/ 3.00'), findsOneWidget);
  });

  probar('notas generales, solo si las hay', (tester) async {
    await abrirDetalle(tester, notas: 'Llamar antes de entregar');

    expect(find.text('Notas generales'), findsOneWidget);
    expect(find.text('Llamar antes de entregar'), findsOneWidget);
  });

  probar('tocar el cliente abre su ficha', (tester) async {
    await abrirDetalle(tester);

    await tester.tap(find.text('Ana García'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Ana García'), findsOneWidget);
    expect(find.text('1 encargo · S/ 0.00 pagado'), findsOneWidget);
  });

  probar('un enlace a un encargo que no está en el teléfono no rompe', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();

    unawaited(contenedor(tester).read(routerProvider).push(Rutas.encargo('no-existe')));
    await tester.pumpAndSettle();

    expect(find.text('Este encargo no existe.'), findsOneWidget);
  });

  probar('todo lo tocable mide al menos 56dp y el texto tiene contraste (Doc 6)', (tester) async {
    await abrirDetalle(tester, entregaEnDias: -3, prometidaEnDias: -5, notas: 'Nota');

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
