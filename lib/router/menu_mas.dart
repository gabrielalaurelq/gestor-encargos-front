import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'rutas.dart';

/// Menú "Más" (Doc 6, Bloque 2): agrupa lo importante pero menos frecuente,
/// a dos toques en vez de competir por espacio en la barra inferior.
class MenuMas extends StatelessWidget {
  const MenuMas({super.key});

  static const opciones = [
    (Rutas.balanceCarga, Icons.bar_chart, 'Balance de carga'),
    (Rutas.cajaDiaria, Icons.payments_outlined, 'Caja diaria'),
    (Rutas.catalogoServicios, Icons.list_alt, 'Catálogo de servicios'),
    (Rutas.ajustes, Icons.settings_outlined, 'Ajustes'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(
        children: [
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
