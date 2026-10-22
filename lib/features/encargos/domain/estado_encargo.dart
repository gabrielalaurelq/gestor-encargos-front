/// Los seis estados del encargo (Doc 2), con los mismos códigos que el
/// backend y el nombre que ve el usuario. Las transiciones válidas las decide
/// el backend; acá solo se leen y se muestran.
enum EstadoEncargo {
  ingresado('INGRESADO', 'Ingresado'),
  enProceso('EN_PROCESO', 'En proceso'),
  listo('LISTO', 'Listo'),
  entregado('ENTREGADO', 'Entregado'),
  pausado('PAUSADO', 'Pausado'),
  cancelado('CANCELADO', 'Cancelado');

  const EstadoEncargo(this.codigo, this.etiqueta);

  /// Como viaja en la API y se guarda en Drift.
  final String codigo;
  final String etiqueta;

  /// `null` para un código que esta versión de la app no conoce (un estado
  /// agregado después en el backend): se muestra tal cual, sin romper la
  /// pantalla.
  static EstadoEncargo? desde(String codigo) {
    for (final estado in values) {
      if (estado.codigo == codigo) return estado;
    }
    return null;
  }

  /// Ya no se trabaja ni se entrega (Doc 2 regla 10).
  bool get cerrado => this == entregado || this == cancelado;
}
