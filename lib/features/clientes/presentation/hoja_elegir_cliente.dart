import 'package:flutter/material.dart';

import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/mensaje_pantalla.dart';
import '../domain/cliente.dart';
import 'buscador_clientes.dart';
import 'hoja_cliente.dart';

/// "Elegir cliente" de Crear Encargo (PRD módulo 2, paso 1): la misma
/// búsqueda de la pestaña Clientes y, si no está, crearlo sin salir del
/// flujo (la `HojaCliente` del S1b). Devuelve el cliente elegido o creado.
class HojaElegirCliente extends StatelessWidget {
  const HojaElegirCliente({super.key});

  static Future<Cliente?> abrir(BuildContext context) => showModalBottomSheet<Cliente>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const FractionallySizedBox(heightFactor: 0.9, child: HojaElegirCliente()),
  );

  Future<void> _crear(BuildContext context, String texto) async {
    final resultado = await HojaCliente.abrirConBusqueda(context, texto);
    // Creado, o el que ya tenía ese teléfono ("Ver a…"): cualquiera sirve.
    if (resultado != null && context.mounted) Navigator.pop(context, resultado.cliente);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Medidas.espacio),
            child: Row(
              children: [
                Expanded(
                  child: Text('Elegir cliente', style: Theme.of(context).textTheme.titleLarge),
                ),
                TextButton.icon(
                  onPressed: () => _crear(context, ''),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Nuevo'),
                ),
              ],
            ),
          ),
          Expanded(
            child: BuscadorClientes(
              autofocus: true,
              alElegir: (cliente) => Navigator.pop(context, cliente),
              alCrear: (texto) => _crear(context, texto),
              vacio: MensajePantalla(
                icono: Icons.people_outline,
                texto: 'Aún no tienes clientes.',
                accion: FilledButton(
                  onPressed: () => _crear(context, ''),
                  child: const Text('Crear cliente'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
