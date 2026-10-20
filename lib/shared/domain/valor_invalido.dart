/// Un Value Object rechazó su valor. El [codigo] es el mismo que devolvería
/// el backend (catálogo del Doc 5, Bloque 3), para que la app muestre el mismo
/// mensaje tanto si el error lo detecta ella, sin conexión, como si llega de
/// la API.
class ValorInvalido implements Exception {
  const ValorInvalido(this.codigo, this.mensaje);

  final String codigo;
  final String mensaje;

  @override
  String toString() => 'ValorInvalido($codigo): $mensaje';
}
