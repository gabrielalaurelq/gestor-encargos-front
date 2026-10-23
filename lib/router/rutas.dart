/// Árbol de rutas del Doc 7 (Bloque 2), en un solo lugar para que ninguna
/// pantalla escriba un path a mano.
///
/// No hay rutas para Objetos, Trabajos, Pagos, Notas ni Fotos: son secciones
/// apiladas dentro del detalle del encargo (Doc 6), no destinos propios.
abstract final class Rutas {
  /// Pantalla en blanco mientras se leen los tokens al arrancar (milisegundos):
  /// evita que el Dashboard asome un instante antes de saber si hay sesión.
  static const arranque = '/arranque';
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

  /// Lo que el servidor rechazó (Doc 7 v1.2). Se llega desde "Más" y desde el
  /// detalle de un encargo afectado, así que vive fuera del shell.
  static const cambiosNoGuardados = '/cambios-no-guardados';
  static String cliente(String id) => '/clientes/$id';

  /// Crear Encargo con el cliente ya elegido, desde su ficha. Crear Encargo
  /// (Sprint 2) lee el parámetro `cliente`.
  static String nuevoEncargoPara(String clienteId) =>
      Uri(path: nuevoEncargo, queryParameters: {'cliente': clienteId}).toString();
  static String encargo(String id) => '/encargos/$id';

  /// La lista detrás de un número del Dashboard (S5b): `activos` o `saldo`.
  static String listaEncargos(String filtro) => '/encargos/lista/$filtro';
}
