import '../../../shared/infrastructure/auth/almacen_tokens.dart';
import '../../../shared/infrastructure/http/cliente_api.dart';

/// Lo que devuelve `POST /auth/login` (Doc 5, Bloque 1).
class SesionNueva {
  const SesionNueva({required this.tokens, required this.negocioId});

  final Tokens tokens;

  /// El negocio se crea en el primer login (Doc 5): siempre viene.
  final String negocioId;
}

/// Endpoints de sesión y dispositivo del Doc 5.
class SesionRemota {
  const SesionRemota(this._api);

  final ClienteApi _api;

  Future<SesionNueva> iniciar(String idToken) async {
    final json = await _api.post('/auth/login', cuerpo: {'id_token': idToken}) as Map;
    final negocio = json['negocio'] as Map;
    return SesionNueva(
      tokens: Tokens(
        access: json['access_token'] as String,
        refresh: json['refresh_token'] as String,
      ),
      negocioId: negocio['id'] as String,
    );
  }

  /// Borra la fila de `dispositivos` en el servidor: invalida el refresh token
  /// **y** el token de notificaciones en una sola llamada (Doc 5). Por eso no
  /// hace falta además `DELETE /dispositivos/fcm-token`, que el Doc 7 pedía al
  /// cerrar sesión: ese endpoint es para silenciar sin salir.
  Future<void> cerrar() => _api.post('/auth/logout');

  Future<void> registrarTokenNotificaciones(String token) =>
      _api.post('/dispositivos/fcm-token', cuerpo: {'fcm_token': token});
}
