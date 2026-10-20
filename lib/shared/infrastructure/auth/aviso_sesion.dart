import 'dart:async';

/// Canal por el que la infraestructura avisa que la sesión terminó sin que el
/// usuario la cerrara (refresh token rechazado: logout desde otro lado, o
/// vencido).
///
/// Existe para no invertir capas: `ClienteApi` (shared) detecta el fin de la
/// sesión, pero quien decide qué hacer —volver a `/login`— es la feature de
/// sesión. El cliente HTTP solo emite; la feature escucha.
class AvisoSesion {
  final _expiradas = StreamController<void>.broadcast(sync: true);

  Stream<void> get expiradas => _expiradas.stream;

  void sesionExpirada() => _expiradas.add(null);

  Future<void> cerrar() => _expiradas.close();
}
