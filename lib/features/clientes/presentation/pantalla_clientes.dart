import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router/rutas.dart';
import '../../../shared/presentation/widgets/mensaje_pantalla.dart';
import '../domain/cliente.dart';
import 'buscador_clientes.dart';
import 'hoja_cliente.dart';

/// Lista de Clientes con búsqueda en tiempo real (Doc 6, pantalla 3; PRD
/// módulo 1).
class PantallaClientes extends StatelessWidget {
  const PantallaClientes({super.key});

  Future<void> _crear(BuildContext context, {String texto = ''}) async {
    final resultado = await HojaCliente.abrirConBusqueda(context, texto);
    if (!context.mounted) return;
    switch (resultado) {
      case ClienteGuardado(:final cliente):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('${cliente.nombre} agregado')));
      case ClienteExistenteElegido(:final cliente):
        _abrirFicha(context, cliente);
      case null:
        break;
    }
  }

  void _abrirFicha(BuildContext context, Cliente cliente) =>
      context.push(Rutas.cliente(cliente.id));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton(
        // Sin Hero: el shell mantiene vivas las pestañas (indexedStack) y dos
        // botones (+) con la etiqueta por defecto chocan al abrir otra pantalla.
        heroTag: null,
        tooltip: 'Agregar cliente',
        onPressed: () => _crear(context),
        child: const Icon(Icons.person_add_alt, size: 30),
      ),
      body: BuscadorClientes(
        alElegir: (cliente) => _abrirFicha(context, cliente),
        alCrear: (texto) => _crear(context, texto: texto),
        vacio: const MensajePantalla(
          icono: Icons.people_outline,
          texto: 'Aún no tienes clientes. Toca + para agregar el primero.',
        ),
        // Que el botón (+) no tape el último cliente.
        relleno: const EdgeInsets.only(bottom: 96),
      ),
    );
  }
}
