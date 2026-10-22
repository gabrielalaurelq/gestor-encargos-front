import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/rutas.dart';
import '../../../shared/infrastructure/http/error_api.dart';
import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/mensaje_pantalla.dart';
import '../../../shared/sync/providers.dart';
import '../application/cambios.dart';
import '../data/cambios_no_guardados.dart';

/// "Cambios no guardados" (Doc 7 v1.2, decisión del usuario: solo
/// "Descartar"): lo que el servidor rechazó, con su motivo. Descartar vuelve
/// a la versión del servidor; el negociante rehace el cambio si aún aplica.
class PantallaCambiosNoGuardados extends ConsumerWidget {
  const PantallaCambiosNoGuardados({super.key});

  Future<void> _descartar(BuildContext context, WidgetRef ref, CambioNoGuardado cambio) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar este cambio?'),
        content: const Text('Se perderá este cambio y verás la versión guardada en el servidor.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Descartar')),
        ],
      ),
    );
    if (confirmado != true || !context.mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    String aviso;
    try {
      await ref.read(descarteProvider).descartar(cambio.operacion);
      aviso = 'Cambio descartado';
    } on SinConexion {
      aviso = 'Necesitas conexión para descartar.';
    } on ErrorApi {
      aviso = 'No se pudo descartar. Intenta de nuevo.';
    }
    mensajero
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(aviso)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cambios = ref.watch(cambiosNoGuardadosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cambios no guardados')),
      body: switch (cambios) {
        AsyncValue(:final List<CambioNoGuardado> value) when value.isEmpty => const MensajePantalla(
          icono: Icons.cloud_done_outlined,
          texto: 'Todo está guardado.',
        ),
        AsyncValue(:final List<CambioNoGuardado> value) => ListView(
          padding: const EdgeInsets.all(Medidas.espacio),
          children: [
            Text(
              'El servidor no aceptó estos cambios. Descártalos para ver lo que quedó '
              'guardado y, si todavía hace falta, vuelve a hacerlos.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final cambio in value) ...[
              const SizedBox(height: Medidas.espacio),
              _Tarjeta(cambio: cambio, alDescartar: () => _descartar(context, ref, cambio)),
            ],
          ],
        ),
        AsyncError() => MensajePantalla.error(
          texto: 'No se pudo mostrar la lista.',
          alReintentar: () => ref.invalidate(cambiosNoGuardadosProvider),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.cambio, required this.alDescartar});

  final CambioNoGuardado cambio;
  final VoidCallback alDescartar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final encargoId = cambio.encargoId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Medidas.espacio),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.sync_problem, color: Colores.ambar),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${cambio.accion} · ${cambio.sobre}',
                    style: tema.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(cambio.motivo),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (encargoId != null)
                  OutlinedButton(
                    onPressed: () => context.push(Rutas.encargo(encargoId)),
                    child: const Text('Ver encargo'),
                  ),
                FilledButton(onPressed: alDescartar, child: const Text('Descartar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
