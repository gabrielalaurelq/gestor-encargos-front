import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/mensaje_pantalla.dart';
import '../application/clientes.dart';
import '../domain/cliente.dart';

/// Búsqueda en tiempo real de clientes (PRD módulo 1): filtra mientras se
/// escribe, sin botón "buscar", sobre la base local. La comparten la pestaña
/// Clientes y la hoja "Elegir cliente" de Crear Encargo.
class BuscadorClientes extends ConsumerStatefulWidget {
  const BuscadorClientes({
    super.key,
    required this.alElegir,
    required this.alCrear,
    required this.vacio,
    this.autofocus = false,
    this.relleno = EdgeInsets.zero,
  });

  final void Function(Cliente) alElegir;

  /// "Crear cliente «texto»" cuando la búsqueda no encuentra nada.
  final void Function(String texto) alCrear;

  /// Lo que se ve si todavía no hay ningún cliente.
  final Widget vacio;
  final bool autofocus;

  /// Margen al pie de la lista (que un botón flotante no tape el último).
  final EdgeInsets relleno;

  @override
  ConsumerState<BuscadorClientes> createState() => _EstadoBuscadorClientes();
}

class _EstadoBuscadorClientes extends ConsumerState<BuscadorClientes> {
  final _busqueda = TextEditingController();
  String _texto = '';

  /// Lo último mostrado: al cambiar el texto, la consulta nueva tarda unos
  /// milisegundos y la lista no debe parpadear vacía mientras tanto.
  List<Cliente>? _ultimos;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  void _limpiar() {
    _busqueda.clear();
    setState(() => _texto = '');
  }

  @override
  Widget build(BuildContext context) {
    final busqueda = ref.watch(busquedaClientesProvider(_texto));
    final clientes = busqueda.value ?? _ultimos;
    if (busqueda.hasValue) _ultimos = busqueda.value;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Medidas.espacio, 8, Medidas.espacio, 8),
          child: TextField(
            controller: _busqueda,
            autofocus: widget.autofocus,
            onChanged: (texto) => setState(() => _texto = texto),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o celular',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _texto.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar búsqueda',
                      onPressed: _limpiar,
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        Expanded(
          child: switch ((busqueda, clientes)) {
            (AsyncError(), _) => MensajePantalla.error(
              texto: 'No se pudo mostrar la lista de clientes.',
              alReintentar: () => ref.invalidate(busquedaClientesProvider(_texto)),
            ),
            // La base local responde al instante (Doc 6: "Cargando" casi no
            // se ve).
            (_, null) => const SizedBox.shrink(),
            (_, final List<Cliente> lista) when lista.isEmpty && _texto.trim().isEmpty =>
              widget.vacio,
            (_, final List<Cliente> lista) when lista.isEmpty => MensajePantalla(
              icono: Icons.search_off,
              texto: 'No hay clientes con «${_texto.trim()}».',
              accion: FilledButton(
                onPressed: () => widget.alCrear(_texto),
                child: Text('Crear cliente «${_texto.trim()}»'),
              ),
            ),
            (_, final List<Cliente> lista) => ListView.builder(
              padding: widget.relleno,
              itemCount: lista.length,
              itemBuilder: (_, i) => _Fila(cliente: lista[i], alTocar: widget.alElegir),
            ),
          },
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.cliente, required this.alTocar});

  final Cliente cliente;
  final void Function(Cliente) alTocar;

  @override
  Widget build(BuildContext context) {
    final telefono = cliente.telefono;
    return ListTile(
      leading: const Icon(Icons.person_outline, size: 28),
      title: Text(cliente.nombre),
      subtitle: telefono == null ? null : Text(telefono.formatear()),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => alTocar(cliente),
    );
  }
}
