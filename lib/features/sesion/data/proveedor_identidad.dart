/// Quién prueba que el usuario es quien dice ser: Google Sign-In vía Firebase
/// Authentication (Doc 3, ADR-009). Puerto, para que la sesión se pruebe sin
/// Google ni plataforma nativa.
abstract class ProveedorIdentidad {
  /// Abre el selector de cuentas y devuelve el ID token de Firebase que pide
  /// `POST /auth/login`. `null` si el usuario lo cerró sin elegir cuenta.
  ///
  /// Lanza [IdentidadNoDisponible] si el build no puede iniciar sesión.
  Future<String?> obtenerIdToken();

  /// Olvida la cuenta elegida, para que el próximo ingreso vuelva a mostrar
  /// el selector (un teléfono compartido, o el negocio cambió de cuenta).
  Future<void> cerrar();
}

class IdentidadNoDisponible implements Exception {
  const IdentidadNoDisponible();
}

/// Google o Firebase no respondieron por falta de red.
class IdentidadSinConexion implements Exception {
  const IdentidadSinConexion();
}

/// El proveedor de un build sin `google-services.json` (local o de prueba):
/// Firebase no arrancó y no hay con qué ingresar. El real es
/// `ProveedorIdentidadGoogle`.
class ProveedorIdentidadNoConfigurado implements ProveedorIdentidad {
  const ProveedorIdentidadNoConfigurado();

  @override
  Future<String?> obtenerIdToken() async => throw const IdentidadNoDisponible();

  @override
  Future<void> cerrar() async {}
}
