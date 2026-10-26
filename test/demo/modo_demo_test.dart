import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/demo/modo_demo.dart';
import 'package:gestor_encargos/features/sesion/application/sesion.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/sync/numeracion.dart';

void main() {
  late BaseDatos base;

  setUp(() => base = BaseDatos(NativeDatabase.memory()));
  tearDown(() => base.close());

  test('el build normal no es de demostración', () => expect(modoDemo, isFalse));

  test('deja lo que el servidor daría al entrar: orígenes, números y nombre', () async {
    await prepararDemo(base);

    final origenes = await base.select(base.origenesPago).get();
    expect([for (final o in origenes) o.nombre], ['Efectivo', 'Transferencia', 'Yape', 'Plin']);
    expect(await base.leerMetadato(Numeracion.claveRangos), '[[1,999999]]');
    expect(await base.leerMetadato(claveNombreNegocio), 'Negocio de prueba');
  });

  test('abrir otra vez no pisa lo ya usado', () async {
    await prepararDemo(base);
    await base.guardarMetadato(Numeracion.claveRangos, '[[42,999999]]');
    await base.guardarMetadato(claveNombreNegocio, 'Taller Rosa');

    await prepararDemo(base);

    expect(await base.leerMetadato(Numeracion.claveRangos), '[[42,999999]]');
    expect(await base.leerMetadato(claveNombreNegocio), 'Taller Rosa');
    expect(await base.select(base.origenesPago).get(), hasLength(4));
  });
}
