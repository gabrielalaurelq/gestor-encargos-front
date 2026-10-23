import 'package:url_launcher/url_launcher.dart';

/// Abre un enlace fuera de la app (deep link de WhatsApp, PRD módulo 9; Doc
/// 7: vive en `infrastructure`). Detrás de una interfaz para que los tests
/// vean el enlace exacto sin abrir nada.
abstract interface class AbridorEnlaces {
  /// `false` si el sistema no pudo abrirlo; nunca lanza.
  Future<bool> abrir(Uri enlace);
}

/// La implementación real: la app externa que corresponda (WhatsApp, o el
/// navegador con la página de `wa.me` si WhatsApp no está instalado).
class AbridorEnlacesSistema implements AbridorEnlaces {
  const AbridorEnlacesSistema();

  @override
  Future<bool> abrir(Uri enlace) async {
    try {
      return await launchUrl(enlace, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }
}
