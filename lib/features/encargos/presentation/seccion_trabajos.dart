import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../application/encargos.dart';
import '../domain/encargo.dart';
import '../domain/estado_encargo.dart';
import '../domain/trabajo.dart';
import 'hoja_agregar_trabajo.dart';
import 'hoja_trabajo.dart';

/// Sección "Trabajos" del Detalle (Doc 6: apilada y visible, no en pestañas).
/// El chip "Catálogo" distingue el precio fijo del personalizado. Con el
/// encargo entregado o cancelado se ve pero no se cambia (decisión del
/// usuario).
class SeccionTrabajos extends ConsumerWidget {
  const SeccionTrabajos({super.key, required this.encargo});

  final Encargo encargo;

  void _avisar(BuildContext context, String texto) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _agregar(BuildContext context) async {
    final agregado = await HojaAgregarTrabajo.abrir(context, encargo.id);
    if (agregado == true && context.mounted) _avisar(context, 'Trabajo agregado');
  }

  Future<void> _abrir(BuildContext context, Trabajo trabajo) async {
    final accion = await HojaTrabajo.abrir(context, trabajo);
    if (!context.mounted) return;
    switch (accion) {
      case AccionTrabajo.guardado:
        _avisar(context, 'Cambios guardados');
      case AccionTrabajo.eliminado:
        _avisar(context, 'Trabajo eliminado');
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final trabajos = ref.watch(trabajosProvider(encargo.id)).value ?? const <Trabajo>[];
    final estado = encargo.estado;
    final cerrado = estado?.cerrado ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Medidas.espacio),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Trabajos', style: tema.textTheme.titleMedium),
            if (trabajos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Todavía no hay trabajos.'),
              )
            else
              for (final trabajo in trabajos)
                _Fila(trabajo: trabajo, alTocar: cerrado ? null : () => _abrir(context, trabajo)),
            const SizedBox(height: 8),
            if (cerrado)
              Text(
                estado == EstadoEncargo.entregado
                    ? 'Ya fue entregado: los trabajos no se cambian.'
                    : 'Está cancelado: los trabajos no se cambian.',
                style: tema.textTheme.bodySmall,
              )
            else
              OutlinedButton.icon(
                onPressed: () => _agregar(context),
                icon: const Icon(Icons.add),
                label: const Text('Agregar trabajo'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.trabajo, required this.alTocar});

  final Trabajo trabajo;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: alTocar,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Medidas.toqueMinimo),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(trabajo.descripcion),
                    if (trabajo.delCatalogo) const _ChipCatalogo(),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(trabajo.precio.formatear(), style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ChipCatalogo extends StatelessWidget {
  const _ChipCatalogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colores.ambarFondo,
        borderRadius: BorderRadius.circular(Medidas.radio),
      ),
      child: Text(
        'Catálogo',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colores.ambar),
      ),
    );
  }
}
