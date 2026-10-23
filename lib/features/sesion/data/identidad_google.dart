import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'proveedor_identidad.dart';

/// Google Sign-In → Firebase Authentication → ID token de Firebase, que es
/// lo que verifica `POST /auth/login` (Doc 3, ADR-009). Solo se usa si
/// Firebase arrancó (ver `iniciarFirebase`).
class ProveedorIdentidadGoogle implements ProveedorIdentidad {
  ProveedorIdentidadGoogle({this.clienteWeb});

  /// El ID de cliente web de Firebase. Opcional: sin él, Google Sign-In lo
  /// toma del `google-services.json` del build.
  final String? clienteWeb;

  Future<void>? _inicio;
  final _google = GoogleSignIn.instance;

  @override
  Future<String?> obtenerIdToken() async {
    try {
      await (_inicio ??= _google.initialize(serverClientId: clienteWeb));
      final cuenta = await _google.authenticate();
      final tokenGoogle = cuenta.authentication.idToken;
      if (tokenGoogle == null) throw const IdentidadNoDisponible();
      final credencial = GoogleAuthProvider.credential(idToken: tokenGoogle);
      final resultado = await FirebaseAuth.instance.signInWithCredential(credencial);
      return await resultado.user?.getIdToken();
    } on GoogleSignInException catch (error) {
      return switch (error.code) {
        GoogleSignInExceptionCode.canceled || GoogleSignInExceptionCode.interrupted => null,
        _ => throw const IdentidadNoDisponible(),
      };
    } on FirebaseAuthException catch (error) {
      if (error.code == 'network-request-failed') throw const IdentidadSinConexion();
      throw const IdentidadNoDisponible();
    }
  }

  /// La sesión de la app es la del backend; la de Firebase solo sirvió para
  /// conseguir el token, así que se cierran las dos.
  @override
  Future<void> cerrar() async {
    await FirebaseAuth.instance.signOut();
    await _google.signOut();
  }
}
