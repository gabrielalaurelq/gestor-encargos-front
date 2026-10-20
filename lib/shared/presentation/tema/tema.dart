import 'package:flutter/material.dart';

import 'colores.dart';

/// Medidas del sistema de diseño (Doc 6, Bloque 1).
abstract final class Medidas {
  /// Área táctil mínima: 56dp, más que los 48dp de Material, por posible
  /// dificultad motriz (Doc 0 §12.2).
  static const toqueMinimo = 56.0;

  /// Texto de cuerpo: 18sp como mínimo (vs. ~14sp típico), por presbicia.
  static const textoCuerpo = 18.0;

  static const radio = 12.0;
  static const espacio = 16.0;
}

/// Tema de la app. Roboto no se declara: es la fuente del sistema en Android
/// y empaquetarla inflaría la app (Doc 7, Bloque 4).
///
/// Los tamaños son en sp y **no se limita el escalado del sistema**: si el
/// usuario agranda la letra en Ajustes de Android, la app la agranda también
/// (Doc 6, accesibilidad). Por eso ningún widget fija alturas que corten
/// texto: los mínimos son mínimos, no alturas fijas.
ThemeData temaGestor() {
  const esquema = ColorScheme(
    brightness: Brightness.light,
    primary: Colores.acento,
    onPrimary: Colores.sobreAcento,
    secondary: Colores.acento,
    onSecondary: Colores.sobreAcento,
    error: Colores.rojo,
    onError: Colores.superficie,
    surface: Colores.superficie,
    onSurface: Colores.texto,
    onSurfaceVariant: Colores.textoSecundario,
    outline: Colores.borde,
    outlineVariant: Colores.borde,
  );

  const tamanoMinimo = Size(Medidas.toqueMinimo, Medidas.toqueMinimo);
  final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Medidas.radio));
  const textoBoton = TextStyle(fontSize: Medidas.textoCuerpo, fontWeight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Colores.fondo,
    // Material encoge las áreas táctiles a 48dp en ciertos widgets; acá no.
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: Medidas.textoCuerpo),
      bodyMedium: TextStyle(fontSize: Medidas.textoCuerpo),
      // Lo más chico que se permite: etiquetas y ayudas, nunca texto de lectura.
      bodySmall: TextStyle(fontSize: 16, color: Colores.textoSecundario),
      labelLarge: textoBoton,
    ).apply(bodyColor: Colores.texto, displayColor: Colores.texto),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colores.fondo,
      foregroundColor: Colores.texto,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colores.texto),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: tamanoMinimo, shape: forma, textStyle: textoBoton),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: tamanoMinimo,
        shape: forma,
        textStyle: textoBoton,
        side: const BorderSide(color: Colores.borde, width: 1.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: tamanoMinimo, shape: forma, textStyle: textoBoton),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: tamanoMinimo)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Colores.acento,
      foregroundColor: Colores.sobreAcento,
      sizeConstraints: BoxConstraints.tightFor(width: 64, height: 64),
      shape: CircleBorder(),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 12,
      minTileHeight: Medidas.toqueMinimo,
      titleTextStyle: TextStyle(fontSize: Medidas.textoCuerpo, color: Colores.texto),
      subtitleTextStyle: TextStyle(fontSize: 16, color: Colores.textoSecundario),
    ),
    cardTheme: CardThemeData(
      color: Colores.superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.radio),
        side: const BorderSide(color: Colores.borde),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colores.superficie,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      hintStyle: const TextStyle(color: Colores.textoTerciario),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medidas.radio),
        borderSide: const BorderSide(color: Colores.borde),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medidas.radio),
        borderSide: const BorderSide(color: Colores.borde),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: Colores.superficie,
      indicatorColor: Colores.ambarFondo,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (estados) => TextStyle(
          fontSize: 16,
          fontWeight: estados.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: estados.contains(WidgetState.selected) ? Colores.acento : Colores.textoSecundario,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (estados) => IconThemeData(
          size: 28,
          color: estados.contains(WidgetState.selected) ? Colores.acento : Colores.textoSecundario,
        ),
      ),
    ),
  );
}
