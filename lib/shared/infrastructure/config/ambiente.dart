/// Configuración por ambiente (Doc 3, Bloque 4: development / staging /
/// production). Llega en tiempo de compilación con `--dart-define`, nunca en
/// un archivo dentro del APK:
///
/// ```bash
/// flutter run --dart-define=API_URL=https://staging.ejemplo.pe/api/v1
/// ```
class Ambiente {
  const Ambiente({required this.apiUrl, this.clienteWebGoogle});

  /// Por defecto, el backend local visto desde el emulador de Android:
  /// `10.0.2.2` es el `localhost` de la máquina anfitriona. Un build de
  /// staging o producción siempre lo sobreescribe.
  static const _apiUrlPorDefecto = 'http://10.0.2.2:3000/api/v1';

  factory Ambiente.desdeCompilacion() => const Ambiente(
    apiUrl: String.fromEnvironment('API_URL', defaultValue: _apiUrlPorDefecto),
    clienteWebGoogle: bool.hasEnvironment('GOOGLE_WEB_CLIENT_ID')
        ? String.fromEnvironment('GOOGLE_WEB_CLIENT_ID')
        : null,
  );

  /// Base de todas las rutas del Doc 5, ya con el prefijo `/api/v1`.
  final String apiUrl;

  /// El ID de cliente web de Firebase (no es secreto). Opcional: sin él,
  /// Google Sign-In lo toma del `google-services.json` del build.
  final String? clienteWebGoogle;
}
