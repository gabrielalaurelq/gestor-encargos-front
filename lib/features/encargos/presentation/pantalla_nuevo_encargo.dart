import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/rutas.dart';
import '../../../shared/domain/dia.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/aviso.dart';
import '../../../shared/presentation/widgets/boton_dictado.dart';
import '../../clientes/application/clientes.dart';
import '../../clientes/domain/cliente.dart';
import '../../clientes/presentation/hoja_elegir_cliente.dart';
import '../application/encargos.dart';
import '../domain/encargo_nuevo.dart';
import 'selector_fecha_entrega.dart';

/// Crear Encargo (Doc 6, pantalla 5; PRD módulo 2, Caso 7): solo cliente,
/// descripción y fecha de entrega; lo demás se agrega después. Al guardar se
/// abre su detalle (decisión del usuario).
class PantallaNuevoEncargo extends ConsumerStatefulWidget {
  const PantallaNuevoEncargo({super.key, this.clienteInicialId});

  /// Desde la ficha del cliente, ya elegido (`?cliente=` en la ruta).
  final String? clienteInicialId;

  @override
  ConsumerState<PantallaNuevoEncargo> createState() => _EstadoPantallaNuevoEncargo();
}

class _EstadoPantallaNuevoEncargo extends ConsumerState<PantallaNuevoEncargo> {
  final _descripcion = TextEditingController();

  /// El elegido en la hoja; mientras no hay, el que vino de la ficha.
  Cliente? _clienteElegido;
  DateTime? _fecha;
  String? _errorCliente;
  String? _errorDescripcion;
  String? _errorFecha;
  bool _guardando = false;

  /// El cliente que vino de la ficha no cuenta como "algo escrito".
  bool get _hayDatos =>
      _descripcion.text.trim().isNotEmpty || _fecha != null || _clienteElegido != null;

  /// El que se muestra y se guarda; lo calcula `build`, que es el único que
  /// puede observar al cliente de la ficha.
  Cliente? _cliente;

  @override
  void initState() {
    super.initState();
    _descripcion.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _elegirCliente() async {
    final cliente = await HojaElegirCliente.abrir(context);
    if (cliente == null || !mounted) return;
    setState(() {
      _clienteElegido = cliente;
      _errorCliente = null;
    });
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    String? descripcion;
    String? errorDescripcion;
    try {
      descripcion = ReglasEncargo.validarDescripcion(_descripcion.text);
    } on ValorInvalido catch (error) {
      errorDescripcion = error.mensaje;
    }
    final cliente = _cliente;
    final fecha = _fecha;
    setState(() {
      _errorCliente = cliente == null ? 'Elige el cliente.' : null;
      _errorDescripcion = errorDescripcion;
      _errorFecha = fecha == null ? 'Elige la fecha de entrega.' : null;
    });
    if (cliente == null || descripcion == null || fecha == null) return;

    setState(() => _guardando = true);
    try {
      final nuevo = await ref
          .read(repositorioEncargosProvider)
          .crear(clienteId: cliente.id, descripcion: descripcion, fechaEntregaAcordada: fecha);
      if (!mounted) return;
      final mensajero = ScaffoldMessenger.of(context);
      // Reemplaza: "atrás" desde el detalle no vuelve al formulario guardado.
      context.pushReplacement(Rutas.encargo(nuevo.id));
      mensajero
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              nuevo.numero == null ? 'Encargo creado' : 'Encargo #${nuevo.numero} creado',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Doc 6, "error imposible": un toque en atrás no tira lo escrito.
  Future<void> _confirmarSalida() async {
    final descartar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar este encargo?'),
        content: const Text('Lo que escribiste se pierde.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir editando'),
          ),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Descartar')),
        ],
      ),
    );
    if (descartar == true && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final id = widget.clienteInicialId;
    _cliente = _clienteElegido ?? (id == null ? null : ref.watch(clienteProvider(id)).value);
    final hoy = hoyDelNegocio();
    final fecha = _fecha;
    final pasada = fecha != null && fecha.isBefore(hoy);
    return PopScope(
      canPop: !_hayDatos,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) unawaited(_confirmarSalida());
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Nuevo encargo')),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Medidas.espacio),
                children: [
                  _CampoCliente(cliente: _cliente, error: _errorCliente, alTocar: _elegirCliente),
                  const SizedBox(height: Medidas.espacio),
                  TextField(
                    controller: _descripcion,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: '¿Qué hay que hacer?',
                      hintText: 'Ej. basta de pantalón azul',
                      errorText: _errorDescripcion,
                      suffixIcon: BotonDictado(controller: _descripcion),
                    ),
                  ),
                  const SizedBox(height: Medidas.espacio),
                  SelectorFechaEntrega(
                    fecha: fecha,
                    hoy: hoy,
                    error: _errorFecha,
                    alCambiar: (dia) => setState(() {
                      _fecha = dia;
                      _errorFecha = null;
                    }),
                  ),
                  if (pasada) ...[
                    const SizedBox(height: Medidas.espacio),
                    // Decisión del usuario: se permite (encargos del cuaderno), con aviso.
                    const Aviso(texto: 'Esa fecha ya pasó. ¿Es correcta?'),
                  ],
                  const SizedBox(height: Medidas.espacio),
                  Text(
                    'Los objetos, trabajos y pagos se agregan después.',
                    style: tema.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            // Fijo abajo, fuera de la lista: siempre a la vista, también con
            // el teclado abierto (el cuerpo se encoge y el botón sube con él).
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Medidas.espacio,
                  8,
                  Medidas.espacio,
                  Medidas.espacio,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    child: Text(pasada ? 'Guardar igual' : 'Guardar encargo'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampoCliente extends StatelessWidget {
  const _CampoCliente({required this.cliente, required this.error, required this.alTocar});

  final Cliente? cliente;
  final String? error;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final elegido = cliente;
    final telefono = elegido?.telefono;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Medidas.radio),
            side: BorderSide(color: error == null ? Colores.borde : Colores.rojo),
          ),
          clipBehavior: Clip.antiAlias,
          child: elegido == null
              ? ListTile(
                  leading: const Icon(Icons.person_search_outlined, size: 28),
                  title: const Text('Elegir cliente'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: alTocar,
                )
              : ListTile(
                  leading: const Icon(Icons.person_outline, size: 28),
                  title: Text(elegido.nombre),
                  subtitle: telefono == null ? null : Text(telefono.formatear()),
                  trailing: TextButton(onPressed: alTocar, child: const Text('Cambiar')),
                  onTap: alTocar,
                ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(error!, style: const TextStyle(color: Colores.rojo, fontSize: 16)),
          ),
      ],
    );
  }
}
