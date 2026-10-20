import 'package:connectivity_plus/connectivity_plus.dart';

/// Avisa cuando el teléfono recupera una red. Puerto, para que el motor de
/// sync se pruebe sin plataforma nativa.
abstract class Conectividad {
  /// Un evento cada vez que se pasa de "sin red" a "con alguna red".
  Stream<void> get recuperada;
}

/// Con `connectivity_plus` (Doc 7, Bloque 3).
///
/// Tener wifi o datos no garantiza internet (un wifi con portal cautivo, por
/// ejemplo): esto solo dispara un intento de sincronizar, y si falla, el
/// motor reintenta con su espera normal. Nunca se usa para decidir "hay red,
/// entonces no encolo".
class ConectividadDispositivo implements Conectividad {
  @override
  Stream<void> get recuperada async* {
    var conectado = true;
    await for (final estado in Connectivity().onConnectivityChanged) {
      final ahora = !estado.every((r) => r == ConnectivityResult.none);
      if (ahora && !conectado) yield null;
      conectado = ahora;
    }
  }
}
