import 'dart:async';
import 'package:drift/drift.dart' show Value;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/router/router.dart';
import 'package:gestor_encargos/router/rutas.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/encargos_prueba.dart';
import '../../../helpers/entorno_prueba.dart';

const marca = '2026-10-01T15:00:00.000Z';

/// La sección Trabajos del Detalle (S3b1) vista por el usuario, con la app
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

  Future<void> servicio(String id, String nombre, int centimos, {bool activo = true}) => entorno
      .base
      .into(entorno.base.servicios)
      .insert(
        ServiciosCompanion.insert(
          id: id,
          creadoEn: marca,
          actualizadoEn: marca,
          nombre: nombre,
          precio: centimos,
          activo: activo,
        ),
      );

  Future<void> trabajo(String id, String descripcion, int centimos, {String? servicioId}) => entorno
      .base
      .into(entorno.base.trabajos)
      .insert(
        TrabajosCompanion.insert(
          id: id,
          creadoEn: marca,
          actualizadoEn: marca,
          encargoId: 'e1',
          servicioId: Value(servicioId),
          descripcion: descripcion,
          precio: centimos,
        ),
      );

  /// Un encargo de Ana con lo que se le pase, y su detalle abierto.
  Future<void> abrirDetalle(
    WidgetTester tester, {
    String estado = 'EN_PROCESO',
    int precioCentimos = 0,
  }) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
    await insertarEncargo(
      entorno.base,
      id: 'e1',
      clienteId: 'ana',
      numero: 47,
      estado: estado,
      creadoEn: marca,
      precioCentimos: precioCentimos,
      saldoCentimos: precioCentimos,
    );
    unawaited(contenedor(tester).read(routerProvider).push(Rutas.encargo('e1')));
    await tester.pumpAndSettle();
    // Debajo de la cabecera y de Objetos recibidos.
    await tester.scrollUntilVisible(
      find.text('Trabajos'),
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

  Future<List<OperacionOutbox>> cola() => entorno.base.select(entorno.base.operacionesOutbox).get();

  Finder campo(String etiqueta) => find.widgetWithText(TextField, etiqueta);

  /// Precio total y saldo (cero pagado: valen lo mismo).
  void totalYSaldo(String texto) =>
      expect(find.text(texto), findsAtLeastNWidgets(2), reason: 'precio total y saldo');

  probar('sin trabajos lo dice y ofrece agregar', (tester) async {
    await abrirDetalle(tester);

    expect(find.text('Trabajos'), findsOneWidget);
    expect(find.text('Todavía no hay trabajos.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Agregar trabajo'), findsOneWidget);
  });

  probar('del catálogo: un toque lo agrega con el chip y el total sube', (tester) async {
    await servicio('s1', 'Basta de jean', 2000);
    await servicio('s2', 'Cierre', 1500);
    await servicio('s3', 'Ya no se hace', 900, activo: false);
    await abrirDetalle(tester);

    await tocar(tester, find.text('Agregar trabajo'));
    expect(find.text('Ya no se hace'), findsNothing, reason: 'los desactivados no se ofrecen');
    await tester.enterText(campo('Buscar servicio'), 'jean');
    await tester.pump();
    expect(find.text('Cierre'), findsNothing);
    await tocar(tester, find.text('Basta de jean'));

    expect(find.text('Trabajo agregado'), findsOneWidget);
    expect(find.text('Catálogo'), findsOneWidget);
    expect(find.text('Basta de jean'), findsOneWidget);
    totalYSaldo('S/ 20.00');
    expect((await cola()).single.cuerpoJson, containsPair('servicio_id', 's1'));
  });

  probar('personalizado: descripción y precio; sin catálogo abre ahí directo', (tester) async {
    await abrirDetalle(tester);

    await tocar(tester, find.text('Agregar trabajo'));
    expect(find.textContaining('no tiene servicios activos'), findsNothing);
    await tocar(tester, find.widgetWithText(FilledButton, 'Agregar'));
    expect(find.text('Escribe qué trabajo es.'), findsOneWidget);
    expect(find.text('Escribe el precio.'), findsOneWidget);

    await tester.enterText(campo('Descripción'), 'Confección de vestido');
    await tester.enterText(campo('Precio'), '180');
    await tester.pump();
    await tocar(tester, find.widgetWithText(FilledButton, 'Agregar'));

    expect(find.text('Trabajo agregado'), findsOneWidget);
    expect(find.text('Confección de vestido'), findsOneWidget);
    expect(find.text('Catálogo'), findsNothing);
    totalYSaldo('S/ 180.00');
  });

  probar('editar un personalizado cambia el precio y el total', (tester) async {
    await trabajo('t1', 'Confección', 10000);
    await abrirDetalle(tester, precioCentimos: 10000);

    await tocar(tester, find.text('Confección'));
    expect(find.text('Editar trabajo'), findsOneWidget);
    await tester.enterText(campo('Precio'), '120');
    await tester.pump();
    await tocar(tester, find.widgetWithText(FilledButton, 'Guardar'));

    expect(find.text('Cambios guardados'), findsOneWidget);
    totalYSaldo('S/ 120.00');
    expect((await cola()).single.cuerpoJson, {'precio': 120});
  });

  probar('uno del catálogo: el precio se ve fijo y la descripción se edita', (tester) async {
    await trabajo('t1', 'Basta de jean', 2000, servicioId: 's1');
    await abrirDetalle(tester, precioCentimos: 2000);

    await tocar(tester, find.text('Basta de jean'));
    expect(campo('Precio'), findsNothing);
    expect(find.textContaining('Precio del catálogo'), findsOneWidget);
    await tester.enterText(campo('Descripción'), 'Basta de jean azul');
    await tester.pump();
    await tocar(tester, find.widgetWithText(FilledButton, 'Guardar'));

    expect(find.text('Basta de jean azul'), findsOneWidget);
    expect((await cola()).single.cuerpoJson, {'descripcion': 'Basta de jean azul'});
  });

  probar('eliminar pide confirmación y el total baja', (tester) async {
    await trabajo('t1', 'Confección', 10000);
    await trabajo('t2', 'Cierre', 1500);
    await abrirDetalle(tester, precioCentimos: 11500);

    await tocar(tester, find.text('Cierre'));
    await tocar(tester, find.text('Eliminar trabajo'));
    expect(find.text('¿Eliminar este trabajo?'), findsOneWidget);
    await tocar(tester, find.widgetWithText(TextButton, 'Eliminar'));

    expect(find.text('Trabajo eliminado'), findsOneWidget);
    expect(find.text('Cierre'), findsNothing);
    totalYSaldo('S/ 100.00');
    expect((await cola()).single.metodo, 'DELETE');
  });

  for (final (estado, motivo) in [
    ('ENTREGADO', 'Ya fue entregado: los trabajos no se cambian.'),
    ('CANCELADO', 'Está cancelado: los trabajos no se cambian.'),
  ]) {
    probar('$estado: se ven pero no se cambian (decisión del usuario)', (tester) async {
      await trabajo('t1', 'Confección', 10000);
      await abrirDetalle(tester, estado: estado, precioCentimos: 10000);

      expect(find.text(motivo), findsOneWidget);
      expect(find.text('Agregar trabajo'), findsNothing);
      await tocar(tester, find.text('Confección'));
      expect(find.text('Editar trabajo'), findsNothing);
    });
  }

  probar('la sección y la hoja cumplen 56dp y contraste (Doc 6)', (tester) async {
    await servicio('s1', 'Basta de jean', 2000);
    await trabajo('t1', 'Basta de jean', 2000, servicioId: 's1');
    await abrirDetalle(tester, precioCentimos: 2000);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    await tocar(tester, find.text('Agregar trabajo'));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
