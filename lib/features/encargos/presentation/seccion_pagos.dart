import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/dia.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/presentation/formato_fecha.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../application/encargos.dart';
import '../domain/encargo.dart';
import '../domain/estado_encargo.dart';
import '../domain/pago.dart';
import 'hoja_registrar_pago.dart';

/// Sección "Pagos" del Detalle (PRD módulo 5): cada pago con fecha, origen,
/// tipo y monto. Un pago no se edita: tocarlo ofrece eliminarlo. Con el
/// encargo cancelado solo se ven; entregado, sí se cobra (decisión del
/// usuario, Doc 7 v1.3).
class SeccionPagos extends ConsumerWidget {
  const SeccionPagos({super.key, required this.encargo});

  final Encargo encargo;

  void _avisar(BuildContext context, String texto) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _registrar(BuildContext context) async {
    final registrado = await HojaRegistrarPago.abrir(context, encargo);
    if (registrado == true && context.mounted) _avisar(context, 'Pago registrado');
  }

  Future<void> _eliminar(BuildContext context, WidgetRef ref, Pago pago) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar este pago?'),
        content: Text('${_resumen(pago)} · ${pago.monto.formatear()}. El saldo se recalcula.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmado != true || !context.mounted) return;
    try {
      await ref.read(repositorioPagosProvider).eliminar(pago);
      if (context.mounted) _avisar(context, 'Pago eliminado');
    } on ValorInvalido catch (error) {
      if (context.mounted) _avisar(context, error.mensaje);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final pagos = ref.watch(pagosProvider(encargo.id)).value ?? const <Pago>[];
    final cancelado = encargo.estado == EstadoEncargo.cancelado;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Medidas.espacio),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pagos', style: tema.textTheme.titleMedium),
            if (pagos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Todavía no hay pagos.'),
              )
            else
              for (final pago in pagos)
                _Fila(pago: pago, alTocar: cancelado ? null : () => _eliminar(context, ref, pago)),
            const SizedBox(height: 8),
            if (cancelado)
              Text('Está cancelado: los pagos solo se ven.', style: tema.textTheme.bodySmall)
            else
              OutlinedButton.icon(
                onPressed: () => _registrar(context),
                icon: const Icon(Icons.add),
                label: const Text('Registrar pago'),
              ),
          ],
        ),
      ),
    );
  }
}

/// "22 oct · Yape · Adelanto". Sin el catálogo bajado no hay nombre de
/// origen y se omite; un tipo desconocido se muestra con su código.
String _resumen(Pago pago) {
  final hoy = hoyDelNegocio();
  return [
    formatearDia(pago.fecha, conAnio: pago.fecha.year != hoy.year),
    ?pago.origenNombre,
    pago.tipo?.etiqueta ?? pago.tipoCodigo,
  ].join(' · ');
}

class _Fila extends StatelessWidget {
  const _Fila({required this.pago, required this.alTocar});

  final Pago pago;
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
                child: Text(_resumen(pago)),
              ),
            ),
            const SizedBox(width: 12),
            Text(pago.monto.formatear(), style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
