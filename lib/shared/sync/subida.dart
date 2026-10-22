import '../infrastructure/http/cliente_api.dart';
import '../infrastructure/http/error_api.dart';
import 'outbox.dart';

typedef Preparador = Future<OperacionOutbox> Function(OperacionOutbox operacion);

Future<OperacionOutbox> _sinCambios(OperacionOutbox operacion) async => operacion;

/// Mitad "push" del motor (Doc 5, Bloque 1): no hay endpoint especial, cada
/// operación de la Outbox se reenvía como la llamada REST normal, **en el
/// orden en que se hizo**.
///
/// Por cada operación, según cómo responde el servidor:
/// - **Bien** (incluido el `200` de un alta repetida, Doc 5 v1.3) → sale de
///   la cola.
/// - **`DELETE` con `404`** → sale de la cola como hecho: lo que se quería
///   (que no exista) ya es cierto, por ejemplo si otro teléfono lo borró.
/// - **Error permanente** (`400`/`404`/`409`/`422`) → se **aparta** y la cola
///   sigue (decisión del usuario): una operación rechazada no frena las
///   demás.
/// - **Error transitorio** (sin red, 5xx, 429) → se detiene la subida y el
///   error sube al motor, que reintenta más tarde **desde esa misma
///   operación**: saltarla rompería el orden.
/// - **Sesión terminada** → se detiene igual, sin apartar: la operación no
///   tiene nada malo y sube cuando se vuelva a entrar.
class Subida {
  Subida({required this._api, required this._outbox, Preparador? preparar})
    : _preparar = preparar ?? _sinCambios;

  final ClienteApi _api;
  final Outbox _outbox;
  final Preparador _preparar;

  Future<int>? _enCurso;

  /// Cuántas operaciones subieron. Una sola subida a la vez: dos en paralelo
  /// enviarían la misma operación dos veces.
  Future<int> subir() => _enCurso ??= _subir().whenComplete(() => _enCurso = null);

  Future<int> _subir() async {
    var subidas = 0;
    while (true) {
      final siguiente = await _outbox.siguiente();
      if (siguiente == null) return subidas;
      final operacion = await _preparar(siguiente);
      try {
        await _enviar(operacion);
      } on ErrorApi catch (error) {
        final yaBorrado =
            operacion.metodo == 'DELETE' && error is ErrorRechazado && error.status == 404;
        if (yaBorrado) {
          await _outbox.completar(operacion.id);
          subidas++;
          continue;
        }
        if (error.esPermanente) {
          await _outbox.apartar(operacion.id, error);
          continue;
        }
        await _outbox.registrarFallo(operacion.id, error);
        rethrow;
      }
      await _outbox.completar(operacion.id);
      subidas++;
    }
  }

  Future<Object?> _enviar(OperacionOutbox operacion) {
    final cuerpo = operacion.cuerpoJson;
    return switch (operacion.metodo) {
      'POST' => _api.post(operacion.ruta, cuerpo: cuerpo),
      'PATCH' => _api.patch(operacion.ruta, cuerpo: cuerpo),
      'DELETE' => _api.delete(operacion.ruta),
      final otro => throw StateError('Método no soportado en la Outbox: $otro'),
    };
  }
}
