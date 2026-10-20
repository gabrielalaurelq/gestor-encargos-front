import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/sync/numeracion.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';

import '../../helpers/adaptador_falso.dart';

void main() {
  late AdaptadorFalso backend;
  late BaseDatos base;
  late Numeracion numeracion;
  late Outbox outbox;
  var siguienteBloque = 101;

  setUp(() {
    backend = AdaptadorFalso();
    base = BaseDatos(NativeDatabase.memory());
    numeracion = Numeracion(base: base, api: clienteApiDePrueba(backend));
    outbox = Outbox(base);
    siguienteBloque = 101;
    // Como el backend: bloques de 100, nunca repetidos.
    backend.cuando('POST /encargos/reservar-bloque-numeros', (_) {
      final desde = siguienteBloque;
      siguienteBloque += 100;
      return Respuesta(200, {'desde': desde, 'hasta': desde + 99});
    });
  });
  tearDown(() async {
    await outbox.cerrar();
    await base.close();
  });

  test('sin bloque reservado no hay número (el encargo se crea igual)', () async {
    expect(await numeracion.tomar(), isNull);
  });

  test('reserva un bloque y entrega sus números en orden, sin tocar la red', () async {
    await numeracion.reservarSiHaceFalta();

    expect([await numeracion.tomar(), await numeracion.tomar()], [101, 102]);
    expect(backend.contar('POST /encargos/reservar-bloque-numeros'), 1);
    expect(await numeracion.restantes(), 98);
  });

  test('con más de 10 restantes no reserva otro', () async {
    await numeracion.reservarSiHaceFalta();
    await numeracion.reservarSiHaceFalta();

    expect(backend.contar('POST /encargos/reservar-bloque-numeros'), 1);
  });

  test('con 10 o menos pide el siguiente y pasa de uno a otro sin hueco', () async {
    await numeracion.reservarSiHaceFalta();
    for (var i = 0; i < 90; i++) {
      await numeracion.tomar();
    }
    expect(await numeracion.restantes(), 10);

    await numeracion.reservarSiHaceFalta();
    final numeros = [for (var i = 0; i < 11; i++) await numeracion.tomar()];

    expect(numeros.first, 191);
    expect(numeros[9], 200);
    expect(numeros.last, 201, reason: 'sigue con el bloque de reserva');
    expect(await numeracion.restantes(), 99);
  });

  test('tomar dentro de una transacción que falla no gasta el número', () async {
    await numeracion.reservarSiHaceFalta();

    await expectLater(
      base.transaction(() async {
        await numeracion.tomar();
        throw StateError('falló el alta del encargo');
      }),
      throwsStateError,
    );

    expect(await numeracion.tomar(), 101);
  });

  group('encargo creado sin número (bloque agotado sin conexión)', () {
    Future<OperacionOutbox> encolarSinNumero() async {
      await base
          .into(base.encargos)
          .insert(
            EncargosCompanion.insert(
              id: 'e1',
              creadoEn: '2026-10-20T10:00:00.000Z',
              actualizadoEn: '2026-10-20T10:00:00.000Z',
              clienteId: 'c1',
              descripcion: 'Basta',
              estado: 'RECIBIDO',
              precioTotal: 0,
              descuento: 0,
              saldoPendiente: 0,
              fechaEntregaPrometida: '2026-10-25',
              fechaEntregaAcordada: '2026-10-25',
            ),
          );
      await outbox.encolar(
        const OperacionNueva(
          tipo: TiposOperacion.crearEncargo,
          metodo: 'POST',
          ruta: '/encargos',
          cuerpo: {'id': 'e1', 'cliente_id': 'c1'},
          entidadId: 'e1',
        ),
      );
      return (await outbox.siguiente())!;
    }

    test('se numera justo antes de subir: la operación y la fila local', () async {
      final operacion = await encolarSinNumero();
      await numeracion.reservarSiHaceFalta();

      final numerada = await numeracion.numerarSiFalta(operacion);

      expect(numerada.cuerpoJson!['numero'], 101);
      expect((await outbox.siguiente())!.cuerpoJson!['numero'], 101, reason: 'persistido');
      expect((await base.select(base.encargos).getSingle()).numero, 101);
    });

    test('sin bloque todavía, sale como está', () async {
      final operacion = await encolarSinNumero();

      final numerada = await numeracion.numerarSiFalta(operacion);

      expect(numerada.cuerpoJson!.containsKey('numero'), isFalse);
    });

    test('un encargo que ya tenía número no gasta otro', () async {
      await numeracion.reservarSiHaceFalta();
      await outbox.encolar(
        const OperacionNueva(
          tipo: TiposOperacion.crearEncargo,
          metodo: 'POST',
          ruta: '/encargos',
          cuerpo: {'id': 'e1', 'numero': 7},
          entidadId: 'e1',
        ),
      );

      await numeracion.numerarSiFalta((await outbox.siguiente())!);

      expect(await numeracion.restantes(), 100);
    });
  });
}
