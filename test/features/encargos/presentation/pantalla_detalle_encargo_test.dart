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
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/presentation/formato_fecha.dart';
import 'package:gestor_encargos/shared/presentation/tema/colores.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

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
    // Van al final, debajo de Trabajos y Pagos.
    await tester.scrollUntilVisible(
      find.text('Notas generales'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

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

  group('editar encargo (S2c; decisión del usuario: una sola hoja)', () {
    Finder campo(String etiqueta) => find.widgetWithText(TextField, etiqueta);

    Future<void> abrirHoja(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Editar encargo'));
      await tester.pumpAndSettle();
    }

    Future<void> guardar(WidgetTester tester, [String texto = 'Guardar']) async {
      await tester.ensureVisible(find.widgetWithText(FilledButton, texto));
      await tester.tap(find.widgetWithText(FilledButton, texto));
      await tester.pumpAndSettle();
    }

    Future<Map<String, Object?>?> ultimoCuerpo() async {
      final ops = await entorno.base.select(entorno.base.operacionesOutbox).get();
      return ops.where((o) => o.metodo == 'PATCH').lastOrNull?.cuerpoJson;
    }

    probar('abre con los datos y guarda solo lo cambiado; la cabecera se actualiza', (
      tester,
    ) async {
      await abrirDetalle(tester);
      await abrirHoja(tester);

      expect(find.text('Editar encargo'), findsOneWidget);
      expect(tester.widget<TextField>(campo('Ubicación (opcional)')).controller!.text, 'Cajón 3');
      await tester.enterText(campo('¿Qué hay que hacer?'), 'Vestido de noche azul');
      await tester.enterText(campo('Ubicación (opcional)'), 'Bolsa 12');
      await guardar(tester);

      expect(find.text('Cambios guardados'), findsOneWidget);
      expect(find.text('Vestido de noche azul'), findsOneWidget);
      expect(find.text('Bolsa 12'), findsOneWidget);
      expect(await ultimoCuerpo(), {
        'descripcion': 'Vestido de noche azul',
        'ubicacion_fisica': 'Bolsa 12',
      });
    });

    probar('reprogramar: recuerda la primera promesa y la cabecera la muestra', (tester) async {
      await abrirDetalle(tester, entregaEnDias: 2);
      await abrirHoja(tester);

      await tester.tap(find.text('En 1 semana'));
      await tester.pumpAndSettle();
      expect(find.text('La primera promesa (${dia(2)}) queda guardada.'), findsOneWidget);
      await guardar(tester);

      expect(find.text('Prometido: ${dia(2)}'), findsOneWidget);
      expect(find.text(dia(7)), findsOneWidget);
      expect(await ultimoCuerpo(), {'fecha_entrega_acordada': iso(7)});
    });

    probar('vaciar la ubicación la borra', (tester) async {
      await abrirDetalle(tester);
      await abrirHoja(tester);

      await tester.enterText(campo('Ubicación (opcional)'), '');
      await guardar(tester);

      expect(find.text('Sin ubicación'), findsOneWidget);
      expect(await ultimoCuerpo(), {'ubicacion_fisica': null});
    });

    probar('sin cambios: cierra sin encolar ni avisar', (tester) async {
      await abrirDetalle(tester);
      await abrirHoja(tester);

      await guardar(tester);

      expect(find.text('Editar encargo'), findsNothing);
      expect(find.text('Cambios guardados'), findsNothing);
      expect(await ultimoCuerpo(), isNull);
    });

    probar('descripción vacía: lo marca y no guarda', (tester) async {
      await abrirDetalle(tester);
      await abrirHoja(tester);

      await tester.enterText(campo('¿Qué hay que hacer?'), ' ');
      await guardar(tester);

      expect(find.text('Escribe qué hay que hacer.'), findsOneWidget);
      expect(await ultimoCuerpo(), isNull);
    });

    probar('entregado: la fecha se ve pero no se cambia (decisión del usuario)', (tester) async {
      await abrirDetalle(tester, estado: 'ENTREGADO');
      await abrirHoja(tester);

      expect(find.text('Ya fue entregado: la fecha no se cambia.'), findsOneWidget);
      expect(find.text('En 1 semana'), findsNothing);
      await tester.enterText(campo('Notas generales (opcional)'), 'Recogió la hija');
      await guardar(tester);

      expect(await ultimoCuerpo(), {'notas_generales': 'Recogió la hija'});
    });

    probar('cancelado: tampoco se reprograma', (tester) async {
      await abrirDetalle(tester, estado: 'CANCELADO');
      await abrirHoja(tester);

      expect(find.text('Está cancelado: la fecha no se cambia.'), findsOneWidget);
    });

    probar('la hoja también cumple 56dp y contraste (Doc 6)', (tester) async {
      await abrirDetalle(tester);
      await abrirHoja(tester);
      await tester.tap(find.text('Hoy'));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  });

  group('descuento (S3b2)', () {
    Finder campo(String etiqueta) => find.widgetWithText(TextField, etiqueta);

    Future<void> trabajos(List<int> centimos) async {
      for (final (i, precio) in centimos.indexed) {
        await entorno.base
            .into(entorno.base.trabajos)
            .insert(
              TrabajosCompanion.insert(
                id: 't$i',
                creadoEn: '2026-10-01T15:00:00.000Z',
                actualizadoEn: '2026-10-01T15:00:00.000Z',
                encargoId: 'e1',
                descripcion: 'Trabajo $i',
                precio: precio,
              ),
            );
      }
    }

    Future<void> abrirHoja(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Editar encargo'));
      await tester.pumpAndSettle();
    }

    Future<void> guardar(WidgetTester tester) async {
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
    }

    probar('muestra la suma y el total mientras se escribe, y lo guarda', (tester) async {
      await trabajos([2000, 1300]);
      await abrirDetalle(tester, precioCentimos: 3300, saldoCentimos: 3300);
      await abrirHoja(tester);

      expect(find.text('Suma de trabajos: S/ 33.00 · Total: S/ 33.00'), findsOneWidget);
      await tester.enterText(campo('Descuento (opcional)'), '3');
      await tester.pump();
      expect(find.text('Suma de trabajos: S/ 33.00 · Total: S/ 30.00'), findsOneWidget);
      await guardar(tester);

      expect(find.text('Cambios guardados'), findsOneWidget);
      expect(find.text('Descuento'), findsOneWidget);
      expect(find.text('S/ 3.00'), findsOneWidget);
      expect(find.text('S/ 30.00'), findsAtLeastNWidgets(2), reason: 'total y saldo');
    });

    probar('mayor que la suma: lo marca al instante y no guarda', (tester) async {
      await trabajos([2000]);
      await abrirDetalle(tester, precioCentimos: 2000, saldoCentimos: 2000);
      await abrirHoja(tester);

      await tester.enterText(campo('Descuento (opcional)'), '25');
      await tester.pump();
      expect(
        find.text('El descuento no puede ser mayor a la suma de los trabajos.'),
        findsOneWidget,
      );
      await guardar(tester);

      expect(find.text('Editar encargo'), findsOneWidget, reason: 'la hoja sigue abierta');
      final ops = await entorno.base.select(entorno.base.operacionesOutbox).get();
      expect(ops.where((o) => o.metodo == 'PATCH'), isEmpty);
    });

    probar('sin trabajos: explica que primero hay que agregarlos', (tester) async {
      await abrirDetalle(tester);
      await abrirHoja(tester);

      expect(find.text('Agrega trabajos para poder aplicar un descuento.'), findsOneWidget);
      expect(campo('Descuento (opcional)'), findsNothing);
    });

    probar('entregado: el descuento se ve fijo con el motivo', (tester) async {
      await trabajos([2000]);
      await abrirDetalle(tester, estado: 'ENTREGADO', descuentoCentimos: 300);
      await abrirHoja(tester);

      expect(find.text('Ya fue entregado: el descuento no se cambia.'), findsOneWidget);
      expect(campo('Descuento (opcional)'), findsNothing);
    });
  });
}
