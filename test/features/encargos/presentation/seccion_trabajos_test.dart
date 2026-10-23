import 'dart:async';
import 'package:drift/drift.dart' show Value;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/features/encargos/domain/objeto_recibido.dart';
import 'package:gestor_encargos/features/encargos/domain/trabajo.dart';
import 'package:gestor_encargos/features/encargos/presentation/seccion_trabajos.dart';
import 'package:gestor_encargos/router/router.dart';
import 'package:gestor_encargos/router/rutas.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
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

  Future<void> trabajo(
    String id,
    String descripcion,
    int centimos, {
    String? servicioId,
    String? objeto,
  }) => entorno.base
      .into(entorno.base.trabajos)
      .insert(
        TrabajosCompanion.insert(
          id: id,
          creadoEn: marca,
          actualizadoEn: marca,
          encargoId: 'e1',
          servicioId: Value(servicioId),
          objetoRecibidoId: Value(objeto),
          descripcion: descripcion,
          precio: centimos,
        ),
      );

  Future<void> objeto(String id, String descripcion) => entorno.base
      .into(entorno.base.objetosRecibidos)
      .insert(
        ObjetosRecibidosCompanion.insert(
          id: id,
          creadoEn: '2026-09-30T15:00:00.000Z',
          actualizadoEn: marca,
          encargoId: 'e1',
          descripcion: descripcion,
        ),
      );

  /// Un texto dentro de la sección Trabajos (los objetos también salen en
  /// la suya).
  Finder enTrabajos(String texto) =>
      find.descendant(of: find.byType(SeccionTrabajos), matching: find.text(texto));

  Finder chip(String texto) => find.widgetWithText(ChoiceChip, texto);

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
  void totalYSaldo(String texto) => expect(
    find.text(texto, skipOffstage: false),
    findsAtLeastNWidgets(2),
    reason: 'precio total y saldo (la cabecera puede quedar arriba, fuera de la vista)',
  );

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

  group('por objeto (S3d2)', () {
    probar('sin objetos no se pregunta ni se agrupa', (tester) async {
      await trabajo('t1', 'Confección', 10000);
      await abrirDetalle(tester, precioCentimos: 10000);

      expect(enTrabajos('Sin objeto'), findsNothing);
      await tocar(tester, find.text('Agregar trabajo'));
      expect(find.text('¿Para qué objeto?'), findsNothing);
    });

    probar('agrupa en el orden de los objetos y deja "Sin objeto" al final', (tester) async {
      await objeto('o1', 'Pantalón');
      await objeto('o2', 'Saco');
      await trabajo('t1', 'Entallar', 3000, objeto: 'o2');
      await trabajo('t2', 'Arreglo suelto', 1000);
      await trabajo('t3', 'Basta', 2000, objeto: 'o1');
      await abrirDetalle(tester, precioCentimos: 6000);

      double alto(String texto) => tester.getTopLeft(enTrabajos(texto)).dy;
      final orden = ['Pantalón', 'Basta', 'Saco', 'Entallar', 'Sin objeto', 'Arreglo suelto'];
      for (var i = 1; i < orden.length; i++) {
        expect(alto(orden[i - 1]), lessThan(alto(orden[i])), reason: '${orden[i - 1]} antes');
      }
    });

    probar('agregar para un objeto: "Ninguno" por defecto y el elegido viaja', (tester) async {
      await objeto('o1', 'Pantalón');
      await objeto('o2', 'Saco');
      await abrirDetalle(tester);

      await tocar(tester, find.text('Agregar trabajo'));
      expect(find.text('¿Para qué objeto?'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(chip('Ninguno')).selected, isTrue);
      await tocar(tester, chip('Saco'));
      await tester.enterText(campo('Descripción'), 'Entallar');
      await tester.enterText(campo('Precio'), '30');
      await tester.pump();
      await tocar(tester, find.widgetWithText(FilledButton, 'Agregar'));

      expect(find.text('Trabajo agregado'), findsOneWidget);
      expect(enTrabajos('Saco'), findsOneWidget, reason: 'subtítulo del grupo');
      expect((await cola()).single.cuerpoJson, containsPair('objeto_recibido_id', 'o2'));
    });

    probar('editar: muestra su objeto y "Ninguno" lo desvincula', (tester) async {
      await objeto('o1', 'Pantalón');
      await trabajo('t1', 'Basta', 2000, objeto: 'o1');
      await abrirDetalle(tester, precioCentimos: 2000);

      await tocar(tester, enTrabajos('Basta'));
      expect(tester.widget<ChoiceChip>(chip('Pantalón')).selected, isTrue);
      await tocar(tester, chip('Ninguno'));
      await tocar(tester, find.widgetWithText(FilledButton, 'Guardar'));

      expect(find.text('Cambios guardados'), findsOneWidget);
      expect(enTrabajos('Pantalón'), findsNothing, reason: 'ya no hay grupos');
      expect((await cola()).single.cuerpoJson, {'objeto_recibido_id': null});
    });
  });

  group('agruparPorObjeto', () {
    Trabajo t(String id, [String? objeto]) => Trabajo(
      id: id,
      encargoId: 'e1',
      servicioId: null,
      objetoRecibidoId: objeto,
      descripcion: id,
      precio: Monto.cero,
    );
    const pantalon = ObjetoRecibido(id: 'o1', encargoId: 'e1', descripcion: 'Pantalón');

    /// Cada grupo como "título: ids", para comparar por contenido.
    List<String> grupos(List<Trabajo> trabajos, List<ObjetoRecibido> objetos) => [
      for (final (titulo, grupo) in agruparPorObjeto(trabajos, objetos))
        '$titulo: ${[for (final trabajo in grupo) trabajo.id].join(',')}',
    ];

    test('un objeto sin trabajos no forma grupo', () {
      expect(grupos([t('a')], [pantalon]), ['null: a']);
    });

    test('un vínculo a un objeto que ya no está cuenta como sin objeto (opción a)', () {
      expect(grupos([t('a', 'borrado')], [pantalon]), ['null: a']);
      expect(grupos([t('a', 'o1'), t('b', 'borrado')], [pantalon]), [
        'Pantalón: a',
        'Sin objeto: b',
      ]);
    });
  });

  probar('la sección y la hoja cumplen 56dp y contraste (Doc 6)', (tester) async {
    await servicio('s1', 'Basta de jean', 2000);
    await objeto('o1', 'Pantalón');
    await trabajo('t1', 'Basta de jean', 2000, servicioId: 's1', objeto: 'o1');
    await abrirDetalle(tester, precioCentimos: 2000);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    await tocar(tester, find.text('Agregar trabajo'));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
