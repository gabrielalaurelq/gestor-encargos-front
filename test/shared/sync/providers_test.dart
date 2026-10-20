import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/infrastructure/auth/almacen_tokens.dart';
import 'package:gestor_encargos/shared/infrastructure/conectividad.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/infrastructure/providers.dart';
import 'package:gestor_encargos/shared/sync/outbox.dart';
import 'package:gestor_encargos/shared/sync/providers.dart';

import '../../helpers/adaptador_falso.dart';

class ConectividadFalsa implements Conectividad {
  final _recuperada = StreamController<void>.broadcast();

  void volver() => _recuperada.add(null);

  @override
  Stream<void> get recuperada => _recuperada.stream;
}

/// El cableado real de `shared/sync/providers.dart`: quién dispara al motor y
/// de dónde sale la cuenta de pendientes del cierre de sesión.
void main() {
  late AdaptadorFalso backend;
  late BaseDatos base;
  late ConectividadFalsa red;
  late ProviderContainer contenedor;

  setUp(() {
    backend = AdaptadorFalso();
    base = BaseDatos(NativeDatabase.memory());
    red = ConectividadFalsa();
    contenedor = ProviderContainer(
      overrides: [
        baseDatosProvider.overrideWithValue(base),
        almacenTokensProvider.overrideWithValue(
          AlmacenTokensEnMemoria(const Tokens(access: 'a', refresh: 'r')),
        ),
        clienteApiProvider.overrideWithValue(clienteApiDePrueba(backend)),
        conectividadProvider.overrideWithValue(red),
      ],
    );
    // Sin red, una vuelta disparada termina en fallo con un reintento
    // programado: así se observa que el disparo ocurrió.
    backend.sinRed = true;
  });
  tearDown(() async {
    contenedor.dispose();
    await base.close();
  });

  Future<bool> seDisparo() async {
    await pumpEventQueue();
    return contenedor.read(motorSyncProvider).estado.proximoIntento != null;
  }

  test('encolar una operación dispara una sincronización', () async {
    contenedor.read(motorSyncProvider);

    await contenedor
        .read(outboxProvider)
        .encolar(
          const OperacionNueva(tipo: 'x', metodo: 'POST', ruta: '/clientes', entidadId: 'c1'),
        );

    expect(await seDisparo(), isTrue);
  });

  test('recuperar la red dispara una sincronización', () async {
    contenedor.read(motorSyncProvider);

    red.volver();

    expect(await seDisparo(), isTrue);
  });

  test('cambiosPendientes cuenta la Outbox real (lo usa el cierre de sesión)', () async {
    final sub = contenedor.listen(cambiosPendientesProvider, (_, _) {});
    await contenedor
        .read(outboxProvider)
        .encolar(
          const OperacionNueva(tipo: 'x', metodo: 'POST', ruta: '/clientes', entidadId: 'c1'),
        );
    await pumpEventQueue();

    expect(sub.read().value, 1);
    sub.close();
  });
}
