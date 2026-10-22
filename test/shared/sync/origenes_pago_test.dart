import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/infrastructure/http/error_api.dart';
import 'package:gestor_encargos/shared/sync/origenes_pago.dart';

import '../../helpers/adaptador_falso.dart';

void main() {
  late AdaptadorFalso backend;
  late BaseDatos base;
  late OrigenesPagoRemotos origenes;
  late List<Map<String, Object?>> catalogo;

  setUp(() {
    backend = AdaptadorFalso();
    base = BaseDatos(NativeDatabase.memory());
    origenes = OrigenesPagoRemotos(base: base, api: clienteApiDePrueba(backend));
    catalogo = [
      {'id': 1, 'nombre': 'Efectivo', 'activo': true},
      {'id': 2, 'nombre': 'Transferencia', 'activo': true},
      {'id': 3, 'nombre': 'Yape', 'activo': true},
      {'id': 4, 'nombre': 'Plin', 'activo': false},
    ];
    backend.cuando('GET /origenes-pago', (_) => Respuesta(200, catalogo));
  });
  tearDown(() => base.close());

  Future<List<String>> guardados() async => [
    for (final o in await base.select(base.origenesPago).get()) '${o.id} ${o.nombre} ${o.activo}',
  ];

  test('guarda el catálogo entero, desactivados incluidos', () async {
    await origenes.actualizarSiHaceFalta();

    expect(await guardados(), [
      '1 Efectivo true',
      '2 Transferencia true',
      '3 Yape true',
      '4 Plin false',
    ]);
  });

  test('una vez por arranque: la segunda vuelta no lo pide', () async {
    await origenes.actualizarSiHaceFalta();
    await origenes.actualizarSiHaceFalta();

    expect(backend.contar('GET /origenes-pago'), 1);
  });

  test('si la tabla quedó vacía (cerró sesión), lo vuelve a pedir', () async {
    await origenes.actualizarSiHaceFalta();
    await base.borrarTodo();

    await origenes.actualizarSiHaceFalta();

    expect(backend.contar('GET /origenes-pago'), 2);
    expect(await guardados(), hasLength(4));
  });

  test('lo reemplaza entero: un origen que el servidor ya no lista desaparece', () async {
    await base
        .into(base.origenesPago)
        .insert(OrigenesPagoCompanion.insert(nombre: 'Tarjeta', activo: true));
    catalogo = catalogo.sublist(0, 1);

    await origenes.actualizarSiHaceFalta();

    expect(await guardados(), ['1 Efectivo true']);
  });

  test('sin red: lanza y no toca lo que había', () async {
    await origenes.actualizarSiHaceFalta();
    backend.sinRed = true;
    final otro = OrigenesPagoRemotos(base: base, api: clienteApiDePrueba(backend));

    await expectLater(otro.actualizarSiHaceFalta(), throwsA(isA<SinConexion>()));
    expect(await guardados(), hasLength(4));
  });
}
