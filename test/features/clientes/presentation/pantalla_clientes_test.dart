import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/app.dart';
import 'package:gestor_encargos/features/clientes/application/clientes.dart';
import 'package:gestor_encargos/features/clientes/domain/cliente.dart';
import 'package:gestor_encargos/features/clientes/presentation/hoja_cliente.dart';
import 'package:gestor_encargos/features/clientes/presentation/pantalla_clientes.dart';
import 'package:gestor_encargos/shared/domain/telefono.dart';
import 'package:gestor_encargos/shared/presentation/tema/tema.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../../helpers/entorno_prueba.dart';

/// La pestaña Clientes vista por el usuario (PRD módulo 1), con la app
/// completa y Drift en memoria.
void main() {
  late EntornoPrueba entorno;

  setUp(() => entorno = EntornoPrueba.conSesion());
  // Fuera del tiempo simulado del test: cerrar SQLite no avanza dentro de él.
  tearDown(() => entorno.cerrar());

  void probar(String descripcion, Future<void> Function(WidgetTester) cuerpo) {
    testWidgetsConBase(descripcion, (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await cuerpo(tester);
    });
  }

  Future<void> abrirClientes(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: entorno.overrides, child: const GestorEncargosApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clientes'));
    await tester.pumpAndSettle();
  }

  Future<void> crearEnBase(WidgetTester tester, String nombre, [String? celular]) async {
    final repositorio = ProviderScope.containerOf(
      tester.element(find.byType(PantallaClientes)),
    ).read(repositorioClientesProvider);
    await repositorio.crear(
      nombre: nombre,
      telefono: celular == null ? null : Telefono.peruano(celular),
    );
    await tester.pumpAndSettle();
  }

  Future<void> buscar(WidgetTester tester, String texto) async {
    await tester.enterText(find.widgetWithText(TextField, 'Buscar por nombre o celular'), texto);
    await tester.pumpAndSettle();
  }

  Finder campo(String etiqueta) => find.widgetWithText(TextField, etiqueta);

  Future<List<OperacionOutbox>> cola() => entorno.base.select(entorno.base.operacionesOutbox).get();

  probar('sin clientes: explica qué hacer (Doc 6)', (tester) async {
    await abrirClientes(tester);

    expect(find.text('Aún no tienes clientes. Toca + para agregar el primero.'), findsOneWidget);
  });

  probar('lista con nombre y celular formateado; tocar abre la ficha', (tester) async {
    await abrirClientes(tester);
    await crearEnBase(tester, 'Ana Pérez', '987654321');

    expect(find.text('987 654 321'), findsOneWidget);
    await tester.tap(find.text('Ana Pérez'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Ana Pérez'), findsOneWidget, reason: 'su ficha');
  });

  probar('filtra mientras se escribe, sin tildes ni botón buscar', (tester) async {
    await abrirClientes(tester);
    await crearEnBase(tester, 'María Núñez');
    await crearEnBase(tester, 'Luis Rojas');

    await buscar(tester, 'nunez');

    expect(find.text('María Núñez'), findsOneWidget);
    expect(find.text('Luis Rojas'), findsNothing);

    await tester.tap(find.byTooltip('Borrar búsqueda'));
    await tester.pumpAndSettle();
    expect(find.text('Luis Rojas'), findsOneWidget);
  });

  probar('sin resultados: ofrece crearlo con el nombre buscado', (tester) async {
    await abrirClientes(tester);
    await crearEnBase(tester, 'Luis Rojas');
    await buscar(tester, 'Rosa Quispe');

    expect(find.text('No hay clientes con «Rosa Quispe».'), findsOneWidget);
    await tester.tap(find.text('Crear cliente «Rosa Quispe»'));
    await tester.pumpAndSettle();
    expect(find.text('Rosa Quispe'), findsWidgets);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Rosa Quispe agregado'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Rosa Quispe'), findsOneWidget, reason: 'coincide');
    expect((await cola()).last.cuerpoJson, containsPair('nombre', 'Rosa Quispe'));
  });

  probar('si lo buscado es un número, va al celular y no al nombre', (tester) async {
    await abrirClientes(tester);
    await crearEnBase(tester, 'Luis Rojas');
    await buscar(tester, '912 345 678');

    await tester.tap(find.text('Crear cliente «912 345 678»'));
    await tester.pumpAndSettle();

    final nombre = tester.widget<TextField>(campo('Nombre')).controller!.text;
    final celular = tester.widget<TextField>(campo('Celular (opcional)')).controller!.text;
    expect([nombre, celular], ['', '912 345 678']);
  });

  probar('agregar con celular peruano: se guarda en E.164 sin escribir +51', (tester) async {
    await abrirClientes(tester);

    await tester.tap(find.byTooltip('Agregar cliente'));
    await tester.pumpAndSettle();
    expect(find.text('+51 '), findsOneWidget, reason: 'se ve, no se escribe');
    await tester.enterText(campo('Nombre'), 'Ana');
    await tester.enterText(campo('Celular (opcional)'), '987 654 321');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect((await cola()).single.cuerpoJson, containsPair('telefono', '+51987654321'));
  });

  probar('celular inválido o nombre vacío: muestra el error y no guarda', (tester) async {
    await abrirClientes(tester);
    await tester.tap(find.byTooltip('Agregar cliente'));
    await tester.pumpAndSettle();

    await tester.enterText(campo('Celular (opcional)'), '12345');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe el nombre del cliente.'), findsOneWidget);
    expect(find.text('El celular debe tener 9 dígitos y empezar con 9.'), findsOneWidget);
    expect(await cola(), isEmpty);
  });

  probar('"Número de otro país" pide el número completo con código', (tester) async {
    await abrirClientes(tester);
    await tester.tap(find.byTooltip('Agregar cliente'));
    await tester.pumpAndSettle();
    expect(campo('Teléfono con código de país (opcional)'), findsNothing, reason: 'no por defecto');

    await tester.tap(find.text('Número de otro país'));
    await tester.pumpAndSettle();
    await tester.enterText(campo('Nombre'), 'Pierre');
    await tester.enterText(campo('Teléfono con código de país (opcional)'), '+33 6 12 34 56 78');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect((await cola()).single.cuerpoJson, containsPair('telefono', '+33612345678'));
  });

  group('teléfono repetido (decisión del usuario: avisar sin bloquear)', () {
    Future<void> agregarConCelular(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Agregar cliente'));
      await tester.pumpAndSettle();
      await tester.enterText(campo('Nombre'), 'Anita');
      await tester.enterText(campo('Celular (opcional)'), '987654321');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }

    probar('avisa quién lo tiene y "Guardar igual" lo crea', (tester) async {
      await abrirClientes(tester);
      await crearEnBase(tester, 'Ana Pérez', '987654321');

      await agregarConCelular(tester);
      expect(find.text('Ya tienes a Ana Pérez con este número.'), findsOneWidget);
      expect((await cola()).length, 1, reason: 'todavía no guardó');

      await tester.tap(find.text('Guardar igual'));
      await tester.pumpAndSettle();

      expect(find.text('Anita agregado'), findsOneWidget);
      expect((await cola()).length, 2);
    });

    probar('"Ver a…" abre la ficha del que ya existe, sin crear nada', (tester) async {
      await abrirClientes(tester);
      await crearEnBase(tester, 'Ana Pérez', '987654321');

      await agregarConCelular(tester);
      await tester.tap(find.text('Ver a Ana Pérez'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Ana Pérez'), findsOneWidget, reason: 'su ficha');
      expect((await cola()).length, 1);
    });
  });

  probar('todo lo tocable mide al menos 56dp y el texto tiene contraste (Doc 6)', (tester) async {
    await abrirClientes(tester);
    await crearEnBase(tester, 'Ana Pérez', '987654321');
    await tester.tap(find.byTooltip('Agregar cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(campo('Nombre'), 'Anita');
    await tester.enterText(campo('Celular (opcional)'), '987654321');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Número de otro país')).height,
      greaterThanOrEqualTo(Medidas.toqueMinimo),
    );
  });

  group('editar (la ficha del S1c abre esta misma hoja)', () {
    ResultadoHojaCliente? resultado;

    Future<void> abrirEdicion(WidgetTester tester, Cliente cliente) async {
      resultado = null;
      await tester.pumpWidget(
        ProviderScope(
          overrides: entorno.overrides,
          child: MaterialApp(
            theme: temaGestor(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async =>
                      resultado = await HojaCliente.abrir(context, cliente: cliente),
                  child: const Text('editar'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('editar'));
      await tester.pumpAndSettle();
    }

    probar('abre con los datos; un número extranjero abre en modo internacional', (tester) async {
      await abrirEdicion(
        tester,
        Cliente(id: 'x', nombre: 'Pierre', telefono: Telefono.e164('+33612345678')),
      );

      expect(find.text('Editar cliente'), findsOneWidget);
      expect(campo('Teléfono con código de país (opcional)'), findsOneWidget);
      expect(find.text('+33612345678'), findsOneWidget);
    });

    probar('borrar el celular lo quita (PATCH con null)', (tester) async {
      final container = ProviderContainer(overrides: entorno.overrides);
      addTearDown(container.dispose);
      final ana = await container
          .read(repositorioClientesProvider)
          .crear(nombre: 'Ana', telefono: Telefono.peruano('987654321'));
      await abrirEdicion(tester, ana);
      expect(tester.widget<TextField>(campo('Celular (opcional)')).controller!.text, '987 654 321');

      await tester.enterText(campo('Celular (opcional)'), '');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(resultado, isA<ClienteGuardado>());
      expect(resultado!.cliente.telefono, isNull);
      expect((await cola()).last.cuerpoJson, {'telefono': null});
    });
  });
}
