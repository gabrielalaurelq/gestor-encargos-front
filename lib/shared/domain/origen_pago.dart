/// Por dónde llegó el dinero (Doc 2, invariante 5): Efectivo, Transferencia,
/// Yape, Plin. Lo usan Pagos y, más adelante, la Caja diaria.
class OrigenPago {
  const OrigenPago({required this.id, required this.nombre, required this.activo});

  final int id;
  final String nombre;

  /// Desactivado: ya no se ofrece para pagos nuevos, pero los viejos lo
  /// siguen nombrando.
  final bool activo;
}
