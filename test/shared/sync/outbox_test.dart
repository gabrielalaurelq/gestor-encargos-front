import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/infrastructure/http/error_api.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

OperacionNueva pago(String id, {String encargoId = 'e1'}) => OperacionNueva(
  tipo: 'registrar_pago',
  metodo: 'POST',
  ruta: '/encargos/$encargoId/pagos',
  cuerpo: {'id': id, 'monto': 20},
  entidadId: id,
  encargoId: encargoId,
);

const rechazo = ErrorRechazado(
  codigo: 'MONTO_INVALIDO',
  mensaje: 'El monto debe ser mayor a cero',
  status: 422,
);

void main() {
  late BaseDatos base;
  late Outbox outbox;

  setUp(() {
    base = BaseDatos(NativeDatabase.memory());
    outbox = Outbox(base);
  });
  tearDown(() async {
    await outbox.cerrar();
    await base.close();
  });

  test('siguiente devuelve la más antigua: el orden es el de encolado', () async {
    await outbox.encolar(pago('p1'));
    await outbox.encolar(pago('p2'));

    final primera = await outbox.siguiente();

    expect(primera!.entidadId, 'p1');
    expect(primera.cuerpoJson, {'id': 'p1', 'monto': 20});
  });

  test('una apartada no bloquea la cola', () async {
    final id = await outbox.encolar(pago('p1'));
    await outbox.encolar(pago('p2'));

    await outbox.apartar(id, rechazo);

    expect((await outbox.siguiente())!.entidadId, 'p2');
  });

  test('completar la saca de la cola', () async {
    final id = await outbox.encolar(pago('p1'));

    await outbox.completar(id);

    expect(await outbox.siguiente(), isNull);
  });

  test('un fallo transitorio suma un intento y guarda el código, sin apartarla', () async {
    final id = await outbox.encolar(pago('p1'));

    await outbox.registrarFallo(id, const SinConexion());
    await outbox.registrarFallo(id, const SinConexion());

    final op = await outbox.siguiente();
    expect(op!.intentos, 2);
    expect(op.ultimoError, 'SIN_CONEXION');
  });

  test('protege la fila y la raíz del agregado, de pendientes y de apartadas', () async {
    await outbox.encolar(pago('p1', encargoId: 'e1'));
    final id = await outbox.encolar(pago('p2', encargoId: 'e2'));
    await outbox.apartar(id, rechazo);

    expect(await outbox.idsProtegidos(), {'p1', 'e1', 'p2', 'e2'});
  });

  test('pendientes cuenta solo las que van a subir, y se actualiza solo', () async {
    final cuentas = <int>[];
    final sub = outbox.pendientes().listen(cuentas.add);
    await pumpEventQueue();

    await outbox.encolar(pago('p1'));
    final id = await outbox.encolar(pago('p2'));
    await pumpEventQueue();
    await outbox.apartar(id, rechazo);
    await pumpEventQueue();

    expect(cuentas.first, 0);
    expect(cuentas.last, 1);
    await sub.cancel();
  });

  test('apartadas expone qué se rechazó, sobre qué encargo y por qué', () async {
    final id = await outbox.encolar(pago('p1', encargoId: 'e7'));
    await outbox.apartar(id, rechazo);

    final lista = await outbox.apartadas().first;

    expect(lista.single.encargoId, 'e7');
    expect(lista.single.codigo, 'MONTO_INVALIDO');
    expect(lista.single.mensaje, 'El monto debe ser mayor a cero');
  });

  test('encolar avisa (el motor sube en cuanto puede)', () async {
    var avisos = 0;
    final sub = outbox.encoladas.listen((_) => avisos++);

    await outbox.encolar(pago('p1'));
    await pumpEventQueue();

    expect(avisos, 1);
    await sub.cancel();
  });

  test('encolada dentro de una transacción que falla, no queda (todo o nada)', () async {
    await expectLater(
      base.transaction(() async {
        await outbox.encolar(pago('p1'));
        throw StateError('falló la escritura local');
      }),
      throwsStateError,
    );

    expect(await outbox.siguiente(), isNull);
  });
}
