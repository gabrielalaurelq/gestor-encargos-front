import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/router.dart';
import 'shared/presentation/tema/tema.dart';

/// Raíz de la app. El `ProviderScope` va en `main.dart` (y en cada test), para
/// que los tests puedan sobreescribir providers sin tocar este widget.
class GestorEncargosApp extends ConsumerWidget {
  const GestorEncargosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Gestor de Encargos',
      theme: temaGestor(),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
      // Español de Perú: fechas, nombres de días y textos de los selectores
      // del sistema (calendario, hora) en el idioma del usuario.
      locale: const Locale('es', 'PE'),
      supportedLocales: const [Locale('es', 'PE'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
