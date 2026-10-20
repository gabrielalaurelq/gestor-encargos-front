/// Árbol de rutas del Doc 7 (Bloque 2), en un solo lugar para que ninguna
/// pantalla escriba un path a mano.
///
/// No hay rutas para Objetos, Trabajos, Pagos, Notas ni Fotos: son secciones
/// apiladas dentro del detalle del encargo (Doc 6), no destinos propios.
abstract final class Rutas {
  static const login = '/login';

  // Shell con barra inferior.
  static const dashboard = '/';
  static const clientes = '/clientes';
  static const calendario = '/calendario';
  static const mas = '/mas';
  static const balanceCarga = '/mas/balance-carga';
  static const cajaDiaria = '/mas/caja-diaria';
  static const catalogoServicios = '/mas/catalogo-servicios';
  static const ajustes = '/mas/ajustes';

  // Profundidad 2: pantalla completa, fuera del shell.
  static const nuevoEncargo = '/encargos/nuevo';
  static String cliente(String id) => '/clientes/$id';
  static String encargo(String id) => '/encargos/$id';
}
