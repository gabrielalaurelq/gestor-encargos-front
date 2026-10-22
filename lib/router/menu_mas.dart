import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/presentation/tema/colores.dart';
import '../shared/sync/providers.dart';

import 'rutas.dart';

/// Menú "Más" (Doc 6, Bloque 2): agrupa lo importante pero menos frecuente,
/// a dos toques en vez de competir por espacio en la barra inferior.
class MenuMas extends ConsumerWidget {
  const MenuMas({super.key});

  static const opciones = [
    (Rutas.balanceCarga, Icons.bar_chart, 'Balance de carga'),
    (Rutas.cajaDiaria, Icons.payments_outlined, 'Caja diaria'),
    (Rutas.catalogoServicios, Icons.list_alt, 'Catálogo de servicios'),
    (Rutas.ajustes, Icons.settings_outlined, 'Ajustes'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rechazados = ref.watch(operacionesApartadasProvider).value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(
        children: [
          // Solo si hay algo que atender (Doc 7 v1.2): nunca un banner.
          if (rechazados > 0)
            ListTile(
              leading: const Icon(Icons.sync_problem, size: 28, color: Colores.ambar),
              title: Text('Cambios no guardados ($rechazados)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Rutas.cambiosNoGuardados),
            ),
          for (final (ruta, icono, titulo) in opciones)
            ListTile(
              leading: Icon(icono, size: 28),
              title: Text(titulo),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(ruta),
            ),
        ],
      ),
    );
  }
}
