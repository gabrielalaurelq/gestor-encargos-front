import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barra inferior persistente con los 4 destinos del Doc 6 (Bloque 2):
/// Dashboard · Clientes · Calendario · Más. Solo envuelve esas cuatro ramas;
/// las pantallas de "profundidad 2" se abren encima, sin barra (Doc 7).
class ShellPrincipal extends StatelessWidget {
  const ShellPrincipal({super.key, required this.navegacion});

  final StatefulNavigationShell navegacion;

  static const destinos = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Inicio',
    ),
    NavigationDestination(
      icon: Icon(Icons.people_outline),
      selectedIcon: Icon(Icons.people),
      label: 'Clientes',
    ),
    NavigationDestination(
      icon: Icon(Icons.calendar_month_outlined),
      selectedIcon: Icon(Icons.calendar_month),
      label: 'Calendario',
    ),
    NavigationDestination(icon: Icon(Icons.menu), label: 'Más'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navegacion,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navegacion.currentIndex,
        destinations: destinos,
        // Tocar la pestaña ya activa vuelve a su raíz: es lo que un usuario
        // espera cuando "se perdió" dentro de una sección.
        onDestinationSelected: (indice) =>
            navegacion.goBranch(indice, initialLocation: indice == navegacion.currentIndex),
      ),
    );
  }
}
