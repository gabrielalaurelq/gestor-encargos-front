import 'package:flutter/material.dart';

/// Paleta del sistema de diseño (Doc 6, Bloque 1), tomada de los wireframes
/// aprobados: un solo acento y tres colores semánticos fijos.
///
/// Cada par texto/fondo que se usa en la app está cubierto por
/// `colores_test.dart`, que exige contraste WCAG AA (4.5:1) — el mínimo que
/// fija el Doc 6 para un público de 50-70 años. Un color nuevo entra con su
/// test o no entra.
abstract final class Colores {
  // Acento: botón principal, enlaces, elementos seleccionados.
  static const acento = Color(0xFF8A5A00);
  static const acentoPresionado = Color(0xFF6B4500);

  // Semánticos (Doc 6): verde = pagado/a tiempo, rojo = atrasado,
  // ámbar = pendiente/advertencia. Cada uno con su fondo suave para
  // etiquetas, como en los wireframes.
  static const verde = Color(0xFF2E7D32);
  static const verdeFondo = Color(0xFFEAF4EA);
  static const rojo = Color(0xFFC62828);
  static const rojoFondo = Color(0xFFFDECEC);
  static const ambar = Color(0xFF8A5A00);
  static const ambarFondo = Color(0xFFFDF1DE);

  // Neutros.
  static const texto = Color(0xFF1C1C1A);
  static const textoSecundario = Color(0xFF4A4A47);

  /// Texto terciario y de ejemplo en campos. Los wireframes usaban #8A8A86,
  /// que sobre blanco da 3.5:1 y no llega al AA del Doc 6: se oscurece.
  static const textoTerciario = Color(0xFF6B6B68);
  static const fondo = Color(0xFFF4F3F1);
  static const superficie = Color(0xFFFFFFFF);
  static const borde = Color(0xFFE6E4E0);
  static const sobreAcento = Color(0xFFFFFFFF);
}
