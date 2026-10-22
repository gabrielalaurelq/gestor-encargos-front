import 'package:flutter/material.dart';

import '../../../shared/presentation/formato_fecha.dart';
import '../../../shared/presentation/tema/colores.dart';

/// La fecha de entrega acordada con atajos de un toque (Hoy, Mañana…) y
/// "Otra fecha…" para el calendario. Sin fecha marcada de entrada: de ella
/// dependen alertas y Balance de Carga, y una fecha por defecto pasaría sin
/// que nadie la mire. Se reutiliza al reprogramar.
class SelectorFechaEntrega extends StatelessWidget {
  const SelectorFechaEntrega({
    super.key,
    required this.fecha,
    required this.hoy,
    required this.alCambiar,
    this.error,
  });

  /// Día del negocio elegido; `null` = todavía no.
  final DateTime? fecha;
  final DateTime hoy;
  final ValueChanged<DateTime> alCambiar;
  final String? error;

  static const _atajos = {'Hoy': 0, 'Mañana': 1, 'En 3 días': 3, 'En 1 semana': 7};

  Future<void> _otraFecha(BuildContext context) async {
    final inicial = fecha ?? hoy;
    // El calendario trabaja con fechas locales; acá todo es día UTC.
    final elegida = await showDatePicker(
      context: context,
      initialDate: DateTime(inicial.year, inicial.month, inicial.day),
      // Fechas pasadas permitidas (decisión del usuario: encargos del cuaderno).
      firstDate: DateTime(hoy.year - 1, hoy.month, hoy.day),
      lastDate: DateTime(hoy.year + 2, hoy.month, hoy.day),
      helpText: 'Fecha de entrega',
    );
    if (elegida != null) alCambiar(DateTime.utc(elegida.year, elegida.month, elegida.day));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final elegida = fecha;
    final deAtajo =
        elegida != null && _atajos.values.any((d) => hoy.add(Duration(days: d)) == elegida);
    Widget boton(String texto, bool marcado, VoidCallback alTocar) => marcado
        ? FilledButton(onPressed: alTocar, child: Text(texto))
        : OutlinedButton(onPressed: alTocar, child: Text(texto));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fecha de entrega', style: tema.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final MapEntry(key: texto, value: dias) in _atajos.entries)
              boton(
                texto,
                elegida == hoy.add(Duration(days: dias)),
                () => alCambiar(hoy.add(Duration(days: dias))),
              ),
            boton('Otra fecha…', elegida != null && !deAtajo, () => _otraFecha(context)),
          ],
        ),
        if (elegida != null) ...[
          const SizedBox(height: 8),
          Text(
            'Entrega: ${formatearDia(elegida, conDiaSemana: true, conAnio: elegida.year != hoy.year)}',
            style: tema.textTheme.titleMedium,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: Colores.rojo, fontSize: 16)),
        ],
      ],
    );
  }
}
