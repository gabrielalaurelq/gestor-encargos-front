/// El token de Firebase Cloud Messaging de esta instalación (Doc 7, Bloque 3),
/// que el backend necesita para mandarle los recordatorios (PRD módulo 13).
/// Puerto, por el mismo motivo que `ProveedorIdentidad`.
abstract class TokenNotificaciones {
  /// `null` si el dispositivo no puede recibir notificaciones.
  Future<String?> obtener();

  /// Firebase rota el token cuando quiere; cada nuevo valor se re-registra.
  Stream<String> get rotaciones;
}

/// Build sin Firebase: no hay notificaciones. **Deuda técnica**, la misma que
/// `ProveedorIdentidadNoConfigurado`: la implementación con
/// `firebase_messaging` llega con el proyecto Firebase.
class SinNotificaciones implements TokenNotificaciones {
  const SinNotificaciones();

  @override
  Future<String?> obtener() async => null;

  @override
  Stream<String> get rotaciones => const Stream.empty();
}
