import 'package:firebase_core/firebase_core.dart';

/// Arranca Firebase si el build trae su configuración (`google-services.json`,
/// que inyecta el CI y nunca se versiona). Sin ella —un build local o de
/// prueba— devuelve `false` y la app sigue con el login deshabilitado.
Future<bool> iniciarFirebase() async {
  try {
    await Firebase.initializeApp();
    return true;
  } on Object {
    return false;
  }
}
