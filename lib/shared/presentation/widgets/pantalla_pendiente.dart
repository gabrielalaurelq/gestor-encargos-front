import 'package:flutter/material.dart';

import '../tema/colores.dart';
import '../tema/tema.dart';

/// Pantalla provisional para las rutas del Doc 7 cuyo contenido llega en un
/// sprint posterior (Doc 11). Existe para que el árbol de navegación completo
/// se pueda recorrer y probar desde el Sprint 0, no como diseño final.
class PantallaPendiente extends StatelessWidget {
  const PantallaPendiente({
    super.key,
    required this.titulo,
    required this.icono,
    this.sprint,
    this.accionFlotante,
  });

  final String titulo;
  final IconData icono;

  /// Sprint del Doc 11 en que se construye; solo informativo.
  final String? sprint;

  final Widget? accionFlotante;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      floatingActionButton: accionFlotante,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Medidas.espacio * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 64, color: Colores.textoTerciario),
              const SizedBox(height: Medidas.espacio),
              Text(titulo, style: tema.textTheme.titleMedium, textAlign: TextAlign.center),
              if (sprint != null) ...[
                const SizedBox(height: 8),
                Text(
                  'En construcción · $sprint',
                  style: tema.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
