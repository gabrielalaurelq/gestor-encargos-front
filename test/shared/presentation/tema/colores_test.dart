import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/presentation/tema/colores.dart';

/// Contraste WCAG 2.x entre dos colores opacos.
double contraste(Color a, Color b) {
  double luminancia(Color c) {
    double canal(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
  }

  final la = luminancia(a);
  final lb = luminancia(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Doc 6: mínimo WCAG AA, 4.5:1 para texto normal. Cada par texto/fondo que
/// usa la app tiene que estar acá.
void main() {
  const aa = 4.5;

  final pares = <String, (Color, Color)>{
    'texto sobre fondo': (Colores.texto, Colores.fondo),
    'texto sobre superficie': (Colores.texto, Colores.superficie),
    'secundario sobre fondo': (Colores.textoSecundario, Colores.fondo),
    'secundario sobre superficie': (Colores.textoSecundario, Colores.superficie),
    'terciario sobre fondo': (Colores.textoTerciario, Colores.fondo),
    'terciario sobre superficie': (Colores.textoTerciario, Colores.superficie),
    'blanco sobre acento (botón)': (Colores.sobreAcento, Colores.acento),
    'blanco sobre acento presionado': (Colores.sobreAcento, Colores.acentoPresionado),
    'acento sobre superficie (enlace)': (Colores.acento, Colores.superficie),
    'acento sobre indicador de pestaña': (Colores.acento, Colores.ambarFondo),
    'verde sobre su fondo (etiqueta)': (Colores.verde, Colores.verdeFondo),
    'verde sobre superficie (monto)': (Colores.verde, Colores.superficie),
    'rojo sobre su fondo (etiqueta)': (Colores.rojo, Colores.rojoFondo),
    'rojo sobre superficie': (Colores.rojo, Colores.superficie),
    'ámbar sobre su fondo (etiqueta)': (Colores.ambar, Colores.ambarFondo),
    'blanco sobre verde (botón)': (Colores.superficie, Colores.verde),
    'blanco sobre rojo (botón)': (Colores.superficie, Colores.rojo),
  };

  for (final MapEntry(key: nombre, value: (texto, fondo)) in pares.entries) {
    test('$nombre cumple AA (≥ $aa:1)', () {
      expect(contraste(texto, fondo), greaterThanOrEqualTo(aa));
    });
  }

  test('el gris de los wireframes (#8A8A86) no cumplía AA: por eso se cambió', () {
    expect(contraste(const Color(0xFF8A8A86), Colores.superficie), lessThan(aa));
  });
}
