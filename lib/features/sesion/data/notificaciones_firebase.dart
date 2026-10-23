import 'package:firebase_messaging/firebase_messaging.dart';

import 'token_notificaciones.dart';

/// El token de Firebase Cloud Messaging. Los recordatorios llegan como
/// notificaciones que Android muestra solo con la app cerrada o de fondo.
///
/// **Deuda técnica:**
/// - Con la app abierta, Firebase no los muestra y la app todavía no los
///   escucha (`onMessage`); se resuelve con el módulo 13.
/// - `getToken`/`onTokenRefresh` están obsoletos desde `firebase_messaging`
///   17 en favor de `register`/`onRegistered`, que entregan otro identificador
///   (el FID) con otro modo de envío. El backend envía con el token clásico
///   (`firebase-admin`, `token:`), así que se cambian los dos juntos.
class TokenNotificacionesFirebase implements TokenNotificaciones {
  const TokenNotificacionesFirebase();

  /// En Android 13+ pide el permiso de notificaciones la primera vez. Si el
  /// usuario lo niega, igual se registra el token: puede activarlas después
  /// desde Ajustes sin volver a entrar.
  @override
  Future<String?> obtener() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      // ignore: deprecated_member_use, ver la deuda técnica de la clase.
      return await FirebaseMessaging.instance.getToken();
    } on Exception {
      return null;
    }
  }

  @override
  // ignore: deprecated_member_use, ver la deuda técnica de la clase.
  Stream<String> get rotaciones => FirebaseMessaging.instance.onTokenRefresh;
}
