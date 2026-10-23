import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/boton_dictado.dart';
import '../application/encargos.dart';
import '../domain/objeto_recibido.dart';

/// Lo que pasó en la hoja, para que el Detalle lo confirme.
enum AccionObjeto { agregado, guardado, eliminado }

/// Agregar un objeto recibido (sin [objeto]) o editarlo y eliminarlo. Solo
/// descripción: la foto llega con Fotografías (decisión del usuario).
class HojaObjeto extends ConsumerStatefulWidget {
  const HojaObjeto({super.key, required this.encargoId, this.objeto, this.trabajos = 0});

  final String encargoId;
  final ObjetoRecibido? objeto;

  /// Cuántos trabajos tiene vinculados: la confirmación de eliminar lo dice.
  final int trabajos;

  static Future<AccionObjeto?> abrir(
    BuildContext context,
    String encargoId, {
    ObjetoRecibido? objeto,
    int trabajos = 0,
  }) => showModalBottomSheet<AccionObjeto>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => HojaObjeto(encargoId: encargoId, objeto: objeto, trabajos: trabajos),
  );

  @override
  ConsumerState<HojaObjeto> createState() => _EstadoHojaObjeto();
}

class _EstadoHojaObjeto extends ConsumerState<HojaObjeto> {
  late final _descripcion = TextEditingController(text: widget.objeto?.descripcion ?? '');
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<AccionObjeto?> Function() accion) async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      final resultado = await accion();
      if (mounted) Navigator.pop(context, resultado);
    } on ValorInvalido catch (error) {
      setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _guardar() {
    final repositorio = ref.read(repositorioObjetosProvider);
    final actual = widget.objeto;
    return _ejecutar(() async {
      if (actual == null) {
        await repositorio.agregar(widget.encargoId, descripcion: _descripcion.text);
        return AccionObjeto.agregado;
      }
      final cambio = await repositorio.editar(actual, descripcion: _descripcion.text);
      return cambio ? AccionObjeto.guardado : null;
    });
  }

  Future<void> _eliminar(ObjetoRecibido objeto) async {
    final trabajos = widget.trabajos;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar este objeto?'),
        content: Text(switch (trabajos) {
          0 => '"${objeto.descripcion}" sale del encargo.',
          1 => '"${objeto.descripcion}" sale del encargo. Su trabajo se queda, sin objeto.',
          _ =>
            '"${objeto.descripcion}" sale del encargo. Sus $trabajos trabajos se quedan, '
                'sin objeto.',
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    await _ejecutar(() async {
      await ref.read(repositorioObjetosProvider).eliminar(objeto);
      return AccionObjeto.eliminado;
    });
  }

  @override
  Widget build(BuildContext context) {
    final objeto = widget.objeto;
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
            Text(
              objeto == null ? 'Agregar objeto' : 'Editar objeto',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: Medidas.espacio),
            TextField(
              controller: _descripcion,
              autofocus: objeto == null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _guardar(),
              decoration: InputDecoration(
                labelText: 'Descripción',
                hintText: 'Pantalón azul, tela del cliente…',
                errorText: _error,
                suffixIcon: BotonDictado(controller: _descripcion),
              ),
            ),
            const SizedBox(height: Medidas.espacio),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: Text(objeto == null ? 'Agregar' : 'Guardar'),
            ),
            if (objeto != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _guardando ? null : () => _eliminar(objeto),
                style: OutlinedButton.styleFrom(foregroundColor: Colores.rojo),
                child: const Text('Eliminar objeto'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
