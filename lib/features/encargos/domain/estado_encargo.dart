/// Los seis estados del encargo (Doc 2), con los mismos códigos que el
/// backend y el nombre que ve el usuario. Las transiciones válidas
/// ([destinos]) son una copia de la tabla del backend (`estado-encargo.ts`):
/// el cambio se aplica sin red y el servidor no debe rechazarlo (S4a).
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

  /// A qué estados puede pasar, con el siguiente natural primero. Reglas
  /// (PRD módulo 6, Doc 2 invariante 11):
  ///
  /// - Hacia adelante se puede saltar (de INGRESADO directo a ENTREGADO).
  /// - No se retrocede: de LISTO a EN PROCESO solo pasando por PAUSADO
  ///   (decisión del usuario: se mantiene la regla del backend).
  /// - PAUSADO y CANCELADO se alcanzan desde cualquier estado activo, y
  ///   desde ellos se vuelve al activo que se elija (reactivar).
  /// - ENTREGADO es terminal.
  List<EstadoEncargo> get destinos => switch (this) {
    ingresado => const [enProceso, listo, entregado, pausado, cancelado],
    enProceso => const [listo, entregado, pausado, cancelado],
    listo => const [entregado, pausado, cancelado],
    pausado => const [ingresado, enProceso, listo, entregado, cancelado],
    cancelado => const [ingresado, enProceso, listo, pausado],
    entregado => const [],
  };

  bool puedePasarA(EstadoEncargo destino) => destinos.contains(destino);
}
