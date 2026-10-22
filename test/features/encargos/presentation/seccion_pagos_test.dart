import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/features/encargos/domain/pago.dart';
import 'package:gestor_encargos/router/router.dart';
import 'package:gestor_encargos/router/rutas.dart';
import 'package:gestor_encargos/shared/domain/dia.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/presentation/formato_fecha.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/encargos_prueba.dart';
import '../../../helpers/entorno_prueba.dart';

const marca = '2026-10-01T15:00:00.000Z';

/// La sección Pagos del Detalle (S3c) vista por el usuario, con la app
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

  /// Un encargo de Ana con un trabajo de S/ 50 y su detalle abierto, ya
  /// desplazado hasta Pagos.
  Future<void> abrirDetalle(
    WidgetTester tester, {
    String estado = 'EN_PROCESO',
    bool conCatalogo = true,
    int pagadoCentimos = 0,
  }) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
    final base = entorno.base;
    if (conCatalogo) await insertarOrigenes(base);
    await insertarEncargo(
      base,
      id: 'e1',
      clienteId: 'ana',
      numero: 47,
      estado: estado,
      creadoEn: marca,
      precioCentimos: 5000,
      saldoCentimos: 5000 - pagadoCentimos,
    );
    await base
        .into(base.trabajos)
        .insert(
          TrabajosCompanion.insert(
            id: 't1',
            creadoEn: marca,
            actualizadoEn: marca,
            encargoId: 'e1',
            descripcion: 'Confección',
            precio: 5000,
          ),
        );
    if (pagadoCentimos > 0) {
      await insertarPago(base, id: 'p1', encargoId: 'e1', centimos: pagadoCentimos);
    }
    unawaited(contenedor(tester).read(routerProvider).push(Rutas.encargo('e1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Pagos'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<List<OperacionOutbox>> pagosEnCola() async => [
    for (final op in await entorno.base.select(entorno.base.operacionesOutbox).get())
      if (op.tipo.endsWith('_pago')) op,
  ];

  final registrarPago = find.widgetWithText(OutlinedButton, 'Registrar pago');
  final registrar = find.widgetWithText(FilledButton, 'Registrar');
  final hoy = formatearDia(hoyDelNegocio(), conAnio: false);

  Set<TipoPago> tipoElegido(WidgetTester tester) =>
      tester.widget<SegmentedButton<TipoPago>>(find.byType(SegmentedButton<TipoPago>)).selected;

  probar('sin pagos lo dice y ofrece registrar', (tester) async {
    await abrirDetalle(tester);

    expect(find.text('Todavía no hay pagos.'), findsOneWidget);
    expect(registrarPago, findsOneWidget);
  });

  probar('registrar el saldo completo por Yape: la fila aparece y el saldo queda en cero', (
    tester,
  ) async {
    await abrirDetalle(tester);
    await tocar(tester, registrarPago);

    expect(find.text('Hoy, $hoy'), findsOneWidget);
    expect(tipoElegido(tester), {TipoPago.adelanto}, reason: 'en proceso: adelanto');
    await tocar(tester, find.text('Saldo completo (S/ 50.00)'));
    await tocar(tester, find.widgetWithText(ChoiceChip, 'Yape'));
    await tocar(tester, registrar);

    expect(find.text('Pago registrado'), findsOneWidget);
    expect(find.text('$hoy · Yape · Adelanto'), findsOneWidget);
    final op = (await pagosEnCola()).single;
    expect(op.cuerpoJson, {
      'id': op.entidadId,
      'monto': 50,
      'origen_id': 3,
      'tipo': 'ADELANTO',
      'fecha': isoDesdeDia(hoyDelNegocio()),
    });
    expect((await entorno.base.select(entorno.base.encargos).getSingle()).saldoPendiente, 0);
  });

  probar('sin elegir medio de pago no registra (no viene ninguno marcado)', (tester) async {
    await abrirDetalle(tester);
    await tocar(tester, registrarPago);

    await tester.enterText(find.widgetWithText(TextField, 'Monto'), '20');
    await tester.pump();
    await tocar(tester, registrar);

    expect(find.text('Elige cómo pagó.'), findsOneWidget);
    expect(await pagosEnCola(), isEmpty);
  });

  probar('sin monto lo pide', (tester) async {
    await abrirDetalle(tester);
    await tocar(tester, registrarPago);

    await tocar(tester, find.widgetWithText(ChoiceChip, 'Efectivo'));
    await tocar(tester, registrar);

    expect(find.text('Escribe el monto.'), findsOneWidget);
    expect(await pagosEnCola(), isEmpty);
  });

  probar('listo: propone "Pago"; se puede cambiar a Adelanto', (tester) async {
    await abrirDetalle(tester, estado: 'LISTO');
    await tocar(tester, registrarPago);

    expect(tipoElegido(tester), {TipoPago.pago});
    await tocar(tester, find.text('Adelanto'));
    expect(tipoElegido(tester), {TipoPago.adelanto});
  });

  probar('sin el catálogo bajado lo explica y no deja registrar', (tester) async {
    await abrirDetalle(tester, conCatalogo: false);
    await tocar(tester, registrarPago);

    expect(find.text('Necesitas conexión una vez para cargar los medios de pago.'), findsOneWidget);
    expect(registrar, findsNothing);
  });

  probar('tocar un pago ofrece eliminarlo; al confirmar, el saldo vuelve a subir', (tester) async {
    await abrirDetalle(tester, pagadoCentimos: 2000);
    final fila = find.text('20 oct · Efectivo · Adelanto');
    expect(fila, findsOneWidget);

    await tocar(tester, fila);
    expect(find.text('¿Eliminar este pago?'), findsOneWidget);
    await tocar(tester, find.widgetWithText(TextButton, 'Eliminar'));

    expect(find.text('Pago eliminado'), findsOneWidget);
    expect(find.text('Todavía no hay pagos.'), findsOneWidget);
    expect((await pagosEnCola()).single.metodo, 'DELETE');
    expect((await entorno.base.select(entorno.base.encargos).getSingle()).saldoPendiente, 5000);
  });

  probar('cancelado: los pagos se ven pero no se registran ni se eliminan', (tester) async {
    await abrirDetalle(tester, estado: 'CANCELADO', pagadoCentimos: 2000);

    expect(find.text('Está cancelado: los pagos solo se ven.'), findsOneWidget);
    expect(registrarPago, findsNothing);
    await tocar(tester, find.text('20 oct · Efectivo · Adelanto'));
    expect(find.text('¿Eliminar este pago?'), findsNothing);
  });

  probar('entregado: se sigue cobrando (entregó fiado)', (tester) async {
    await abrirDetalle(tester, estado: 'ENTREGADO', pagadoCentimos: 2000);

    expect(registrarPago, findsOneWidget);
  });
}
