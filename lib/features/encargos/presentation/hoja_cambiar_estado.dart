import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/monto.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../application/encargos.dart';
import '../domain/encargo.dart';
import '../domain/estado_encargo.dart';

/// "Cambiar estado" (PRD módulo 6, Doc 6 flujo "Marcar Listo"): solo los
/// estados a los que se puede pasar ([EstadoEncargo.destinos]), con el
/// siguiente natural primero. Decisiones del usuario (S4):
///
/// - Solo ENTREGADO (no se deshace) y CANCELADO piden confirmación; el resto
///   se aplica al tocar.
/// - Entregar con saldo pendiente pregunta antes ("¿Entregar igual?"): avisa,
///   nunca bloquea (Doc 2, invariante 10).
class HojaCambiarEstado extends ConsumerStatefulWidget {
  const HojaCambiarEstado({super.key, required this.encargo});

  final Encargo encargo;

  /// El estado nuevo, o `null` si no cambió.
  static Future<EstadoEncargo?> abrir(BuildContext context, Encargo encargo) =>
      showModalBottomSheet<EstadoEncargo>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => HojaCambiarEstado(encargo: encargo),
      );

  @override
  ConsumerState<HojaCambiarEstado> createState() => _EstadoHojaCambiarEstado();
}

class _EstadoHojaCambiarEstado extends ConsumerState<HojaCambiarEstado> {
  String? _error;
  bool _guardando = false;

  Future<void> _elegir(EstadoEncargo destino) async {
    if (_guardando) return;
    if (!await _confirmar(destino) || !mounted) return;
    setState(() => _guardando = true);
    try {
      final cambio = await ref
          .read(repositorioEncargosProvider)
          .cambiarEstado(widget.encargo.id, destino);
      if (mounted) Navigator.pop(context, cambio ? destino : null);
    } on ValorInvalido catch (error) {
      setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<bool> _confirmar(EstadoEncargo destino) async {
    final saldo = widget.encargo.saldoPendiente;
    final (titulo, texto, accion) = switch (destino) {
      EstadoEncargo.entregado when saldo > Monto.cero => (
        '¿Entregar igual?',
        'Queda ${saldo.formatear()} por cobrar. Una vez entregado, ya no cambia de estado.',
        'Entregar igual',
      ),
      EstadoEncargo.entregado => (
        '¿Marcar como entregado?',
        'Una vez entregado, ya no cambia de estado.',
        'Entregar',
      ),
      EstadoEncargo.cancelado => (
        '¿Cancelar este encargo?',
        'Sus datos y pagos se conservan. Si fue un error, se puede reactivar.',
        'Cancelar encargo',
      ),
      _ => (null, null, null),
    };
    if (titulo == null) return true;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(texto!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(accion!)),
        ],
      ),
    );
    return confirmado == true;
  }

  /// Una línea de ayuda bajo cada opción: qué pasa al elegirla.
  String? _ayuda(EstadoEncargo actual, EstadoEncargo destino) => switch (destino) {
    EstadoEncargo.listo when widget.encargo.fechaListo == null =>
      'Se anota hoy como el día en que quedó listo.',
    EstadoEncargo.entregado => 'El cliente lo recogió. Ya no cambia de estado.',
    EstadoEncargo.pausado => 'Falta material o el cliente no responde.',
    EstadoEncargo.cancelado => 'Se puede reactivar si fue un error.',
    _ when actual == EstadoEncargo.cancelado || actual == EstadoEncargo.pausado => 'Reactivar.',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final actual = widget.encargo.estado;
    final destinos = actual?.destinos ?? const <EstadoEncargo>[];
    // Solo los secuenciales tienen un "siguiente" claro; desde pausado o
    // cancelado el anterior no se guarda (opción a del S4b).
    final conSiguiente =
        actual == EstadoEncargo.ingresado ||
        actual == EstadoEncargo.enProceso ||
        actual == EstadoEncargo.listo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Medidas.espacio, 0, Medidas.espacio, Medidas.espacio),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cambiar estado', style: tema.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Ahora: ${actual?.etiqueta ?? widget.encargo.codigoEstado}',
              style: tema.textTheme.bodyMedium?.copyWith(color: Colores.textoSecundario),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: tema.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            for (final (i, destino) in destinos.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                minTileHeight: Medidas.toqueMinimo,
                enabled: !_guardando,
                title: Text(
                  destino.etiqueta,
                  style: TextStyle(
                    fontSize: Medidas.textoCuerpo,
                    fontWeight: conSiguiente && i == 0 ? FontWeight.w700 : FontWeight.w500,
                    color: destino == EstadoEncargo.cancelado ? Colores.rojo : null,
                  ),
                ),
                subtitle: switch (_ayuda(actual!, destino)) {
                  final ayuda? => Text(ayuda),
                  null => null,
                },
                trailing: conSiguiente && i == 0
                    ? Text(
                        'Siguiente',
                        style: tema.textTheme.bodySmall?.copyWith(color: Colores.textoSecundario),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () => _elegir(destino),
              ),
          ],
        ),
      ),
    );
  }
}
