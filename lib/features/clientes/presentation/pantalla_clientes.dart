import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/rutas.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/mensaje_pantalla.dart';
import '../application/clientes.dart';
import '../domain/cliente.dart';
import 'hoja_cliente.dart';

/// Lista de Clientes con búsqueda en tiempo real (Doc 6, pantalla 3; PRD
/// módulo 1): filtra mientras se escribe, sin botón "buscar", sobre la base
/// local — funciona igual sin conexión.
class PantallaClientes extends ConsumerStatefulWidget {
  const PantallaClientes({super.key});

  /// Un texto buscado que es un teléfono ("987 654", "+34 612…") prellena el
  /// celular al crear; cualquier otro, el nombre (PRD: "con el texto buscado
  /// prellenado").
  static bool pareceTelefono(String texto) =>
      RegExp(r'\d').hasMatch(texto) && RegExp(r'^\+?[\d\s\-]+$').hasMatch(texto.trim());

  @override
  ConsumerState<PantallaClientes> createState() => _EstadoPantallaClientes();
}

class _EstadoPantallaClientes extends ConsumerState<PantallaClientes> {
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

  Future<void> _crear({String texto = ''}) async {
    final telefono = PantallaClientes.pareceTelefono(texto);
    final resultado = await HojaCliente.abrir(
      context,
      nombreInicial: telefono ? '' : texto.trim(),
      telefonoInicial: telefono ? texto.trim() : '',
    );
    if (!mounted) return;
    switch (resultado) {
      case ClienteGuardado(:final cliente):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('${cliente.nombre} agregado')));
      case ClienteExistenteElegido(:final cliente):
        _abrirFicha(cliente);
      case null:
        break;
    }
  }

  void _abrirFicha(Cliente cliente) => context.push(Rutas.cliente(cliente.id));

  @override
  Widget build(BuildContext context) {
    final busqueda = ref.watch(busquedaClientesProvider(_texto));
    final clientes = busqueda.value ?? _ultimos;
    if (busqueda.hasValue) _ultimos = busqueda.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton(
        // Sin Hero: el shell mantiene vivas las pestañas (indexedStack) y dos
        // botones (+) con la etiqueta por defecto chocan al abrir otra pantalla.
        heroTag: null,
        tooltip: 'Agregar cliente',
        onPressed: _crear,
        child: const Icon(Icons.person_add_alt, size: 30),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Medidas.espacio, 8, Medidas.espacio, 8),
            child: TextField(
              controller: _busqueda,
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
              // La base local responde al instante (Doc 6: "Cargando" casi
              // no se ve).
              (_, null) => const SizedBox.shrink(),
              (_, final List<Cliente> lista) when lista.isEmpty && _texto.trim().isEmpty =>
                const MensajePantalla(
                  icono: Icons.people_outline,
                  texto: 'Aún no tienes clientes. Toca + para agregar el primero.',
                ),
              (_, final List<Cliente> lista) when lista.isEmpty => MensajePantalla(
                icono: Icons.search_off,
                texto: 'No hay clientes con «${_texto.trim()}».',
                accion: FilledButton(
                  onPressed: () => _crear(texto: _texto),
                  child: Text('Crear cliente «${_texto.trim()}»'),
                ),
              ),
              (_, final List<Cliente> lista) => ListView.builder(
                // Que el botón (+) no tape el último cliente.
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: lista.length,
                itemBuilder: (_, i) => _Fila(cliente: lista[i], alTocar: _abrirFicha),
              ),
            },
          ),
        ],
      ),
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
