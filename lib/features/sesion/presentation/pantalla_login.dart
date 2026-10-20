import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../application/sesion.dart';
import '../domain/estado_sesion.dart';

/// Login (Doc 6, pantalla 1): un solo botón. Sin formulario, sin contraseña,
/// sin tour — al entrar se va directo al Dashboard (Doc 6, onboarding mínimo).
/// La navegación la hace el router al cambiar la sesión, no esta pantalla.
class PantallaLogin extends ConsumerStatefulWidget {
  const PantallaLogin({super.key});

  @override
  ConsumerState<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends ConsumerState<PantallaLogin> {
  bool _entrando = false;
  FalloLogin? _fallo;

  static String mensaje(FalloLogin fallo) => switch (fallo) {
    FalloLogin.sinConexion =>
      'No hay internet. La primera vez se necesita conexión para entrar; '
          'después la app funciona sin ella.',
    FalloLogin.rechazado => 'No se pudo comprobar tu cuenta de Google. Inténtalo otra vez.',
    FalloLogin.demasiadosIntentos => 'Demasiados intentos seguidos. Espera un minuto.',
    FalloLogin.noDisponible => 'El ingreso con Google todavía no está configurado en esta versión.',
    FalloLogin.servidor => 'Hubo un problema de nuestro lado. Inténtalo en unos minutos.',
  };

  Future<void> _entrar() async {
    setState(() {
      _entrando = true;
      _fallo = null;
    });
    final fallo = await ref.read(sesionProvider.notifier).iniciarSesion();
    if (!mounted) return;
    setState(() {
      _entrando = false;
      _fallo = fallo;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Medidas.espacio * 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.inventory_2_outlined, size: 72, color: Colores.acento),
                const SizedBox(height: Medidas.espacio),
                Text(
                  'Gestor de Encargos',
                  style: tema.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tus encargos, clientes y pagos en un solo lugar.',
                  style: tema.textTheme.bodyLarge?.copyWith(color: Colores.textoSecundario),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Medidas.espacio * 2),
                FilledButton.icon(
                  onPressed: _entrando ? null : _entrar,
                  icon: _entrando
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.login),
                  label: Text(_entrando ? 'Entrando…' : 'Continuar con Google'),
                ),
                if (_fallo case final fallo?) ...[
                  const SizedBox(height: Medidas.espacio),
                  // liveRegion: TalkBack lo lee apenas aparece.
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(Medidas.espacio),
                      decoration: BoxDecoration(
                        color: Colores.rojoFondo,
                        borderRadius: BorderRadius.circular(Medidas.radio),
                      ),
                      child: Text(
                        mensaje(fallo),
                        style: tema.textTheme.bodyLarge?.copyWith(color: Colores.rojo),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
