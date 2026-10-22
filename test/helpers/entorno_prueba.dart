import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/sesion/application/sesion.dart';
import 'package:gestor_encargos/features/sesion/data/proveedor_identidad.dart';
import 'package:gestor_encargos/features/sesion/data/token_notificaciones.dart';
import 'package:gestor_encargos/features/sesion/domain/estado_sesion.dart';
import 'package:gestor_encargos/shared/infrastructure/auth/almacen_tokens.dart';
import 'package:gestor_encargos/shared/infrastructure/config/ambiente.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';
import 'package:gestor_encargos/shared/infrastructure/http/cliente_api.dart';
import 'package:gestor_encargos/shared/infrastructure/providers.dart';
import 'package:gestor_encargos/shared/sync/motor_sync.dart';
import 'package:gestor_encargos/shared/sync/providers.dart';

import 'adaptador_falso.dart';

/// Google Sign-In falso.
class IdentidadFalsa implements ProveedorIdentidad {
  /// Lo que "elige" el usuario: `null` = cerró el selector sin elegir.
  String? idToken = 'id-token-google';
  bool disponible = true;
  int cierres = 0;

  @override
  Future<String?> obtenerIdToken() async {
    if (!disponible) throw const IdentidadNoDisponible();
    return idToken;
  }

  @override
  Future<void> cerrar() async => cierres++;
}

class NotificacionesFalsas implements TokenNotificaciones {
  String? token;
  final _rotaciones = StreamController<String>.broadcast(sync: true);

  void rotar(String nuevo) => _rotaciones.add(nuevo);

  @override
  Future<String?> obtener() async => token;

  @override
  Stream<String> get rotaciones => _rotaciones.stream;
}

/// Motor de sync que solo cuenta cuántas veces se le pidió sincronizar: los
/// tests de sesión y de pantallas no prueban el motor (eso es `shared/sync/`).
class MotorSyncFalso implements MotorSync {
  int sincronizaciones = 0;

  @override
  Future<void> sincronizar() async => sincronizaciones++;

  @override
  EstadoSync get estado => const EstadoSync();

  @override
  Stream<EstadoSync> get estados => const Stream.empty();

  @override
  void cerrar() {}
}

/// Todo lo que la app toca hacia afuera, reemplazado por dobles: backend,
/// almacenamiento seguro, SQLite en memoria, Google y Firebase Messaging.
class EntornoPrueba {
  EntornoPrueba({Tokens? sesion}) : tokens = AlmacenTokensEnMemoria(sesion);

  /// Con una sesión ya guardada, como un teléfono donde ya se entró.
  factory EntornoPrueba.conSesion() => EntornoPrueba(
    sesion: const Tokens(access: 'access-1', refresh: 'refresh-1'),
  );

  final backend = AdaptadorFalso();
  final AlmacenTokensEnMemoria tokens;
  final base = BaseDatos(NativeDatabase.memory());
  final identidad = IdentidadFalsa();
  final notificaciones = NotificacionesFalsas();
  final motor = MotorSyncFalso();
  int pendientes = 0;

  List<Override> get overrides => [
    almacenTokensProvider.overrideWithValue(tokens),
    baseDatosProvider.overrideWithValue(base),
    clienteApiProvider.overrideWith(
      (ref) => ClienteApi(
        ambiente: const Ambiente(apiUrl: 'http://api.test/api/v1'),
        tokens: tokens,
        adaptador: backend,
        alExpirarSesion: ref.watch(avisoSesionProvider).sesionExpirada,
      ),
    ),
    proveedorIdentidadProvider.overrideWithValue(identidad),
    tokenNotificacionesProvider.overrideWithValue(notificaciones),
    cambiosPendientesProvider.overrideWith((_) => Stream.value(pendientes)),
    motorSyncProvider.overrideWithValue(motor),
  ];

  /// `POST /auth/login` responde como el backend real para [negocioId].
  void loginAceptado({String negocioId = 'negocio-1'}) {
    backend.cuando(
      'POST /auth/login',
      (_) => Respuesta(200, {
        'access_token': 'access-1',
        'refresh_token': 'refresh-1',
        'negocio': {'id': negocioId, 'nombre_negocio': null},
      }),
    );
  }

  Future<void> cerrar() => base.close();
}

/// Espera a que la sesión termine de leer los tokens guardados.
Future<EstadoSesion> sesionCargada(ProviderContainer contenedor) async {
  contenedor.read(sesionProvider);
  for (var i = 0; i < 50; i++) {
    final estado = contenedor.read(sesionProvider);
    if (estado != EstadoSesion.verificando) return estado;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('La sesión no terminó de cargar');
}

/// `testWidgets` para pantallas que leen Drift. Drift suelta sus consultas
/// reactivas con un timer de 0 al desmontarse, y el test fallaría por "timer
/// pendiente": se desmonta la app y se lo deja correr antes de terminar.
///
/// La base del [EntornoPrueba] se cierra en un `tearDown` normal, **no** con
/// `addTearDown` dentro del test: dentro del tiempo simulado, cerrar SQLite
/// no avanza nunca.
///
/// Se desmonta también si el test falla: si no, el timer pendiente deja
/// colgados a los tests siguientes del archivo.
void testWidgetsConBase(String descripcion, Future<void> Function(WidgetTester tester) cuerpo) {
  testWidgets(descripcion, (tester) async {
    try {
      await cuerpo(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}
