import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/router.dart';
import 'shared/presentation/tema/tema.dart';
import 'shared/sync/providers.dart';

/// Raíz de la app. El `ProviderScope` va en `main.dart` (y en cada test), para
/// que los tests puedan sobreescribir providers sin tocar este widget.
class GestorEncargosApp extends ConsumerStatefulWidget {
  const GestorEncargosApp({super.key});

  @override
  ConsumerState<GestorEncargosApp> createState() => _GestorEncargosAppState();
}

class _GestorEncargosAppState extends ConsumerState<GestorEncargosApp> {
  late final AppLifecycleListener _ciclo;

  @override
  void initState() {
    super.initState();
    // Al volver al primer plano se sincroniza: el teléfono pudo pasar horas
    // en segundo plano, y lo que se ve al abrir debe estar al día.
    _ciclo = AppLifecycleListener(
      onResume: () => unawaited(ref.read(motorSyncProvider).sincronizar()),
    );
  }

  @override
  void dispose() {
    _ciclo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
