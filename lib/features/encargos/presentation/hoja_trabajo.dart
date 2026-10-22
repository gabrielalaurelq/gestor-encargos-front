import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/monto.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/campo_precio.dart';
import '../application/encargos.dart';
import '../domain/trabajo.dart';

/// Lo que pasó en la hoja, para que el Detalle lo confirme.
enum AccionTrabajo { guardado, eliminado }

/// Editar o eliminar un trabajo. En uno del catálogo el precio queda fijo
/// (Doc 2, invariante 13) y la descripción sí se edita (decisión del
/// usuario).
class HojaTrabajo extends ConsumerStatefulWidget {
  const HojaTrabajo({super.key, required this.trabajo});

  final Trabajo trabajo;

  static Future<AccionTrabajo?> abrir(BuildContext context, Trabajo trabajo) =>
      showModalBottomSheet<AccionTrabajo>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => HojaTrabajo(trabajo: trabajo),
      );

  @override
  ConsumerState<HojaTrabajo> createState() => _EstadoHojaTrabajo();
}

class _EstadoHojaTrabajo extends ConsumerState<HojaTrabajo> {
  late final _descripcion = TextEditingController(text: widget.trabajo.descripcion);
  late final _precio = TextEditingController(text: textoEditable(widget.trabajo.precio));
  String? _errorDescripcion;
  String? _errorPrecio;
  bool _guardando = false;

  @override
  void dispose() {
    _descripcion.dispose();
    _precio.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<AccionTrabajo?> Function() accion) async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      final resultado = await accion();
      if (mounted) Navigator.pop(context, resultado);
    } on ValorInvalido catch (error) {
      setState(() => _errorDescripcion = error.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _guardar() async {
    final trabajo = widget.trabajo;
    String? errorDescripcion;
    String? errorPrecio;
    Monto? precio;
    try {
      ReglasTrabajo.validarDescripcion(_descripcion.text);
    } on ValorInvalido catch (error) {
      errorDescripcion = error.mensaje;
    }
    if (!trabajo.delCatalogo) {
      try {
        precio = ReglasTrabajo.leerPrecio(_precio.text);
      } on ValorInvalido catch (error) {
        errorPrecio = error.mensaje;
      }
    }
    setState(() {
      _errorDescripcion = errorDescripcion;
      _errorPrecio = errorPrecio;
    });
    if (errorDescripcion != null || errorPrecio != null) return;
    await _ejecutar(() async {
      final cambio = await ref
          .read(repositorioTrabajosProvider)
          .editar(trabajo, descripcion: _descripcion.text, precio: precio);
      return cambio ? AccionTrabajo.guardado : null;
    });
  }

  Future<void> _eliminar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar este trabajo?'),
        content: Text('"${widget.trabajo.descripcion}" sale del encargo y el total se recalcula.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    await _ejecutar(() async {
      await ref.read(repositorioTrabajosProvider).eliminar(widget.trabajo);
      return AccionTrabajo.eliminado;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final trabajo = widget.trabajo;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Medidas.espacio,
        0,
        Medidas.espacio,
        Medidas.espacio + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Editar trabajo', style: tema.textTheme.titleLarge),
            const SizedBox(height: Medidas.espacio),
            TextField(
              controller: _descripcion,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: 'Descripción', errorText: _errorDescripcion),
            ),
            const SizedBox(height: Medidas.espacio),
            if (trabajo.delCatalogo) ...[
              Text('Precio', style: tema.textTheme.bodySmall),
              Text(
                trabajo.precio.formatear(),
                style: const TextStyle(fontSize: Medidas.textoCuerpo, fontWeight: FontWeight.w600),
              ),
              Text(
                'Precio del catálogo. Si necesitas otro precio, elimínalo y agrégalo '
                'como personalizado.',
                style: tema.textTheme.bodySmall,
              ),
            ] else
              CampoPrecio(controller: _precio, errorText: _errorPrecio, alEnviar: _guardar),
            const SizedBox(height: Medidas.espacio),
            FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _guardando ? null : _eliminar,
              style: OutlinedButton.styleFrom(foregroundColor: Colores.rojo),
              child: const Text('Eliminar trabajo'),
            ),
          ],
        ),
      ),
    );
  }
}
