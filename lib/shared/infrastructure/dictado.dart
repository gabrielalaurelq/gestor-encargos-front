import 'package:speech_to_text/speech_to_text.dart';

/// Cómo terminó [Dictado.preparar].
enum PreparacionDictado {
  listo,

  /// El usuario negó el permiso del micrófono.
  sinPermiso,

  /// El teléfono no tiene reconocedor de voz (Android viejo, sin Google).
  noDisponible,
}

/// El dictado por voz nativo del teléfono (PRD módulo 8; Doc 0 §13.1: sin
/// IA, sin costo). Doc 7: vive en `infrastructure`, detrás de una interfaz
/// para que los tests no necesiten micrófono.
abstract interface class Dictado {
  /// Prepara el reconocedor; la primera vez, Android pide el permiso del
  /// micrófono (decisión del usuario P3: al usarlo, no al abrir la app).
  Future<PreparacionDictado> preparar();

  /// Escucha hasta que el usuario calla, toca de nuevo o hay un error.
  /// [alReconocer] recibe todo lo reconocido en esta escucha (crece mientras
  /// se habla); [alTerminar] se llama una vez al final, haya o no texto.
  Future<void> escuchar({
    required void Function(String texto) alReconocer,
    required void Function() alTerminar,
  });

  Future<void> detener();
}

/// La implementación real, con `speech_to_text`. No obliga a reconocer sin
/// conexión: Android lo hace solo si el paquete de español está descargado
/// (PRD módulo 8, nota técnica; Doc 7 v1.4). Sin él y sin red, la escucha
/// falla y el campo queda como estaba.
class DictadoNativo implements Dictado {
  final _voz = SpeechToText();
  bool _preparado = false;
  String? _idioma;
  void Function()? _alTerminar;

  @override
  Future<PreparacionDictado> preparar() async {
    if (_preparado) return PreparacionDictado.listo;
    try {
      _preparado = await _voz.initialize(
        onStatus: (estado) {
          if (estado == SpeechToText.doneStatus || estado == SpeechToText.notListeningStatus) {
            _terminar();
          }
        },
        onError: (_) => _terminar(),
      );
    } on Exception {
      _preparado = false;
    }
    if (_preparado) {
      _idioma = await _elegirIdioma();
      return PreparacionDictado.listo;
    }
    return await _voz.hasPermission
        ? PreparacionDictado.noDisponible
        : PreparacionDictado.sinPermiso;
  }

  /// Español de Perú si el teléfono lo tiene; si no, cualquier español; si
  /// no, el del sistema (`null`).
  Future<String?> _elegirIdioma() async {
    final idiomas = [for (final idioma in await _voz.locales()) idioma.localeId];
    String? primero(bool Function(String) prueba) => idiomas.where(prueba).firstOrNull;
    return primero((id) => id.replaceAll('-', '_').toLowerCase() == 'es_pe') ??
        primero((id) => id.toLowerCase().startsWith('es'));
  }

  @override
  Future<void> escuchar({
    required void Function(String texto) alReconocer,
    required void Function() alTerminar,
  }) async {
    _alTerminar = alTerminar;
    try {
      await _voz.listen(
        onResult: (resultado) => alReconocer(resultado.recognizedWords),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          localeId: _idioma,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(minutes: 1),
        ),
      );
    } on Exception {
      _terminar();
    }
  }

  @override
  Future<void> detener() async {
    await _voz.stop();
    _terminar();
  }

  void _terminar() {
    final alTerminar = _alTerminar;
    _alTerminar = null;
    alTerminar?.call();
  }
}
