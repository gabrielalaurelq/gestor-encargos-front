import 'package:flutter/material.dart';

import '../tema/colores.dart';
import '../tema/tema.dart';

/// Los estados "Vacío" y "Error" del Doc 6 (Bloque 4), iguales en toda la app:
/// ícono, mensaje en lenguaje humano y, si corresponde, la acción que resuelve
/// la situación. Nunca una pantalla en blanco sin explicación.
class MensajePantalla extends StatelessWidget {
  const MensajePantalla({super.key, required this.icono, required this.texto, this.accion});

  /// Error al leer la base local: lenguaje humano y botón de reintentar.
  factory MensajePantalla.error({required String texto, required VoidCallback alReintentar}) =>
      MensajePantalla(
        icono: Icons.error_outline,
        texto: texto,
        accion: OutlinedButton(onPressed: alReintentar, child: const Text('Reintentar')),
      );

  final IconData icono;
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Medidas.espacio * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 64, color: Colores.textoTerciario),
            const SizedBox(height: Medidas.espacio),
            Text(texto, textAlign: TextAlign.center),
            if (accion != null) ...[const SizedBox(height: Medidas.espacio), accion!],
          ],
        ),
      ),
    );
  }
}
