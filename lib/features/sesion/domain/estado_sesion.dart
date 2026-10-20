/// En qué punto está la sesión del dispositivo. De esto depende a qué
/// pantalla deja entrar el router.
enum EstadoSesion {
  /// Al arrancar, mientras se leen los tokens guardados (milisegundos).
  verificando,

  /// Sin tokens: solo se puede estar en `/login`.
  anonima,

  /// Con tokens. No significa "con red": la app funciona offline (Doc 3), y el
  /// access token vencido se renueva solo al volver la conexión.
  iniciada,
}

/// Por qué no se pudo iniciar sesión, para mostrarlo en el login. Cancelar el
/// selector de cuentas de Google **no** es un fallo: no se muestra nada.
enum FalloLogin {
  /// El primer ingreso necesita internet: el negocio se crea en el servidor.
  sinConexion,

  /// Google o el backend rechazaron la identidad (`401` de `/auth/login`).
  rechazado,

  /// Límite de intentos de `/auth/login` (Doc 5: ~10 por minuto por IP).
  demasiadosIntentos,

  /// El inicio con Google no está disponible en este build (sin Firebase).
  noDisponible,

  /// Cualquier otra cosa del servidor (5xx, respuesta inesperada).
  servidor,
}

/// Por qué no se pudo cerrar la sesión. En los tres casos el usuario sigue
/// dentro, con todo intacto.
sealed class FalloCierre {
  const FalloCierre();
}

/// Hay cambios hechos sin conexión que todavía no llegaron al servidor:
/// cerrar sesión los borraría.
class CierreConPendientes extends FalloCierre {
  const CierreConPendientes(this.cantidad);

  final int cantidad;
}

/// Sin red no se puede avisar al servidor. Cerrar solo en el teléfono dejaría
/// la sesión viva del lado del servidor —y este teléfono recibiendo las
/// notificaciones del negocio—, así que se pide conexión.
class CierreSinConexion extends FalloCierre {
  const CierreSinConexion();
}

class CierreFallido extends FalloCierre {
  const CierreFallido();
}
