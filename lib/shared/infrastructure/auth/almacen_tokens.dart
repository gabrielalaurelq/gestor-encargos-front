import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Los dos tokens de la sesión (Doc 5, Bloque 1).
class Tokens {
  const Tokens({required this.access, required this.refresh});

  /// JWT de vida corta (~30 min). Va en cada petición.
  final String access;

  /// Vida larga (90 días), sin rotación. Solo sirve para pedir otro access.
  final String refresh;

  Tokens conAccess(String nuevo) => Tokens(access: nuevo, refresh: refresh);
}

/// Dónde vive la sesión del dispositivo. Puerto, para que los tests usen
/// [AlmacenTokensEnMemoria] sin plataforma nativa.
abstract class AlmacenTokens {
  Future<Tokens?> leer();
  Future<void> guardar(Tokens tokens);
  Future<void> borrar();
}

/// **El refresh token nunca va a `SharedPreferences` ni a la base Drift**: es
/// una credencial de 90 días con la que cualquiera actuaría como el negocio.
/// En Android, `flutter_secure_storage` la cifra con una clave del Keystore.
class AlmacenTokensSeguro implements AlmacenTokens {
  AlmacenTokensSeguro([FlutterSecureStorage? almacen])
    : _almacen = almacen ?? const FlutterSecureStorage();

  final FlutterSecureStorage _almacen;

  static const _claveAccess = 'sesion.access_token';
  static const _claveRefresh = 'sesion.refresh_token';

  @override
  Future<Tokens?> leer() async {
    final valores = await _almacen.readAll();
    final access = valores[_claveAccess];
    final refresh = valores[_claveRefresh];
    if (access == null || refresh == null) return null;
    return Tokens(access: access, refresh: refresh);
  }

  @override
  Future<void> guardar(Tokens tokens) async {
    await _almacen.write(key: _claveAccess, value: tokens.access);
    await _almacen.write(key: _claveRefresh, value: tokens.refresh);
  }

  @override
  Future<void> borrar() async {
    await _almacen.delete(key: _claveAccess);
    await _almacen.delete(key: _claveRefresh);
  }
}

class AlmacenTokensEnMemoria implements AlmacenTokens {
  AlmacenTokensEnMemoria([this._tokens]);

  Tokens? _tokens;

  @override
  Future<Tokens?> leer() async => _tokens;

  @override
  Future<void> guardar(Tokens tokens) async => _tokens = tokens;

  @override
  Future<void> borrar() async => _tokens = null;
}
