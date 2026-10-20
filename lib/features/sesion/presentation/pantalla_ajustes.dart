import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/tema/colores.dart';
import '../application/sesion.dart';
import '../domain/estado_sesion.dart';

/// Ajustes (Doc 6, pantalla 11). Por ahora solo "Cerrar sesión"; el resto
/// (nombre del negocio, umbral de "Cliente no recoge") llega en el Sprint 7.
class PantallaAjustes extends ConsumerWidget {
  const PantallaAjustes({super.key});

  static String mensaje(FalloCierre fallo) => switch (fallo) {
    CierreConPendientes(:final cantidad) =>
      'Tienes ${cantidad == 1 ? '1 cambio' : '$cantidad cambios'} sin enviar. '
          'Conéctate a internet para que se guarden y vuelve a intentarlo.',
    CierreSinConexion() => 'Para cerrar sesión se necesita internet.',
    CierreFallido() => 'No se pudo cerrar la sesión. Inténtalo en unos minutos.',
  };

  Future<void> _cerrarSesion(BuildContext context, WidgetRef ref) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Para volver a entrar necesitarás internet y tu cuenta de Google.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    final fallo = await ref.read(sesionProvider.notifier).cerrarSesion();
    // Si cerró, el router ya está llevando a /login.
    if (fallo == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('No se cerró la sesión'),
        content: Text(mensaje(fallo)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(contexto), child: const Text('Entendido')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.logout, size: 28, color: Colores.rojo),
            title: const Text('Cerrar sesión'),
            onTap: () => _cerrarSesion(context, ref),
          ),
        ],
      ),
    );
  }
}
