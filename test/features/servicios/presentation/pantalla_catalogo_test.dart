import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/servicios/presentation/pantalla_catalogo.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/presentation/tema/tema.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/entorno_prueba.dart';

/// El catálogo visto por el usuario (PRD módulo 4, flujo 3b), contra Drift en
/// memoria: lo que se ve en pantalla sale de la base local, y cada cambio deja
/// su operación en el Outbox.
void main() {
  late EntornoPrueba entorno;

  setUp(() => entorno = EntornoPrueba.conSesion());
  // Fuera del tiempo simulado del test: cerrar SQLite no avanza dentro de él.
  tearDown(() => entorno.cerrar());

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: entorno.overrides,
        child: MaterialApp(theme: temaGestor(), home: const PantallaCatalogo()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<OperacionOutbox>> cola() => entorno.base.select(entorno.base.operacionesOutbox).get();

  Future<void> agregar(WidgetTester tester, String nombre, String precio) async {
    await tester.tap(find.byTooltip('Agregar servicio'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), nombre);
    await tester.enterText(find.widgetWithText(TextField, 'Precio'), precio);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
  }

  Future<void> abrirServicio(WidgetTester tester, String nombre) async {
    await tester.tap(find.text(nombre));
    await tester.pumpAndSettle();
  }

  testWidgetsConBase('vacío: explica qué hacer, nunca una pantalla en blanco (Doc 6)', (
    tester,
  ) async {
    await abrir(tester);

    expect(find.text('Aún no tienes servicios. Toca + para agregar el primero.'), findsOneWidget);
  });

  testWidgetsConBase('agregar: aparece en la lista con su precio y queda por subir', (
    tester,
  ) async {
    await abrir(tester);

    await agregar(tester, 'Basta de jean', '20');

    expect(find.text('Basta de jean'), findsOneWidget);
    expect(find.text('S/ 20.00'), findsOneWidget);
    expect(find.text('Servicio agregado'), findsOneWidget);
    final op = (await cola()).single;
    expect(op.cuerpoJson, containsPair('precio', 20));
  });

  testWidgetsConBase('sin nombre ni precio: muestra los dos errores y no guarda', (tester) async {
    await abrir(tester);

    await agregar(tester, ' ', '');

    expect(find.text('Escribe el nombre del servicio.'), findsOneWidget);
    expect(find.text('Escribe el precio.'), findsOneWidget);
    expect(await cola(), isEmpty);
  });

  testWidgetsConBase('el campo de precio no deja escribir signo ni coma', (tester) async {
    await abrir(tester);
    await tester.tap(find.byTooltip('Agregar servicio'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Precio'), '-1,5');

    expect(find.text('15'), findsOneWidget);
  });

  testWidgetsConBase('editar: el nombre no se toca, el precio sí', (tester) async {
    await abrir(tester);
    await agregar(tester, 'Basta', '20');

    await abrirServicio(tester, 'Basta');
    expect(find.widgetWithText(TextField, 'Nombre'), findsNothing);
    expect(find.text('Para cambiar el nombre, desactívalo y crea uno nuevo.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Precio'), '22.50');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('S/ 22.50'), findsOneWidget);
    expect(find.text('Precio actualizado'), findsOneWidget);
    expect((await cola()).last.cuerpoJson, {'precio': 22.5});
  });

  testWidgetsConBase('guardar sin cambiar el precio no encola nada', (tester) async {
    await abrir(tester);
    await agregar(tester, 'Basta', '20');

    await abrirServicio(tester, 'Basta');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect((await cola()).length, 1, reason: 'solo el alta');
  });

  testWidgetsConBase('desactivar: pasa a "Desactivados" y se deshace desde el aviso', (
    tester,
  ) async {
    await abrir(tester);
    await agregar(tester, 'Basta', '20');

    await abrirServicio(tester, 'Basta');
    await tester.tap(find.text('Desactivar'));
    await tester.pumpAndSettle();

    expect(find.text('Desactivados (1)'), findsOneWidget);
    expect(find.text('Basta'), findsNothing, reason: 'plegado');
    expect(find.text('No tienes servicios activos. Toca + para agregar uno.'), findsOneWidget);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();

    expect(find.text('Basta'), findsOneWidget);
    expect(find.text('Desactivados (1)'), findsNothing);
    final activos = [for (final op in await cola()) op.cuerpoJson?['activo']];
    expect(activos, [null, false, true]);
  });

  testWidgetsConBase('un desactivado se reactiva desde su sección', (tester) async {
    await abrir(tester);
    await agregar(tester, 'Basta', '20');
    await abrirServicio(tester, 'Basta');
    await tester.tap(find.text('Desactivar'));
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(tester.element(find.byType(PantallaCatalogo))).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Desactivados (1)'));
    await tester.pumpAndSettle();
    await abrirServicio(tester, 'Basta');
    await tester.tap(find.text('Reactivar'));
    await tester.pumpAndSettle();

    expect(find.text('Servicio reactivado'), findsOneWidget);
    expect(find.text('Desactivados (1)'), findsNothing);
  });

  testWidgetsConBase('todo lo tocable mide al menos 56dp (Doc 6)', (tester) async {
    await abrir(tester);
    await agregar(tester, 'Basta', '20');
    await abrirServicio(tester, 'Basta');

    for (final tocable in [
      find.byTooltip('Agregar servicio'),
      find.widgetWithText(FilledButton, 'Guardar'),
      find.widgetWithText(OutlinedButton, 'Desactivar'),
    ]) {
      final tamano = tester.getSize(tocable);
      expect(tamano.height, greaterThanOrEqualTo(Medidas.toqueMinimo));
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  test('sinVersionDelServidor ordena antes que cualquier marca real', () {
    expect(sinVersionDelServidor.compareTo('1970-01-01T00:00:00.000Z'), lessThan(0));
  });
}
