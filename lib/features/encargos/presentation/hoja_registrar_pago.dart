import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/dia.dart';
import '../../../shared/domain/monto.dart';
import '../../../shared/domain/origen_pago.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/presentation/formato_fecha.dart';
import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/aviso.dart';
import '../../../shared/presentation/widgets/campo_precio.dart';
import '../application/encargos.dart';
import '../domain/encargo.dart';
import '../domain/pago.dart';

/// "Registrar pago" (PRD módulo 5): monto, medio de pago y tipo. La fecha la
/// pone el teléfono y solo se muestra (Doc 2, invariante 4).
///
/// El medio de pago **no viene marcado** (decisión de diseño del S3c): uno
/// propuesto por defecto se aceptaría sin mirar y ensuciaría la Caja diaria.
class HojaRegistrarPago extends ConsumerStatefulWidget {
  const HojaRegistrarPago({super.key, required this.encargo});

  final Encargo encargo;

  /// `true` si se registró.
  static Future<bool?> abrir(BuildContext context, Encargo encargo) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => HojaRegistrarPago(encargo: encargo),
  );

  @override
  ConsumerState<HojaRegistrarPago> createState() => _EstadoHojaRegistrarPago();
}

class _EstadoHojaRegistrarPago extends ConsumerState<HojaRegistrarPago> {
  final _monto = TextEditingController();
  late TipoPago _tipo = TipoPago.propuestoPara(widget.encargo.estado);
  int? _origenId;
  String? _errorMonto;
  String? _errorOrigen;
  bool _guardando = false;

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    String? errorMonto;
    Monto? monto;
    try {
      monto = ReglasPago.leerMonto(_monto.text);
    } on ValorInvalido catch (error) {
      errorMonto = error.mensaje;
    }
    final origenId = _origenId;
    setState(() {
      _errorMonto = errorMonto;
      _errorOrigen = origenId == null ? 'Elige cómo pagó.' : null;
    });
    if (monto == null || origenId == null || _guardando) return;

    setState(() => _guardando = true);
    try {
      await ref
          .read(repositorioPagosProvider)
          .registrar(widget.encargo.id, monto: monto, origenId: origenId, tipo: _tipo);
      if (mounted) Navigator.pop(context, true);
    } on ValorInvalido catch (error) {
      setState(() {
        if (error.codigo == 'ORIGEN_PAGO_INVALIDO') {
          _errorOrigen = error.mensaje;
        } else {
          _errorMonto = error.mensaje;
        }
      });
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final saldo = widget.encargo.saldoPendiente;
    final origenes = ref.watch(origenesActivosProvider);
    final sinCatalogo = origenes.value?.isEmpty ?? false;
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
            Text('Registrar pago', style: tema.textTheme.titleLarge),
            Text(
              'Hoy, ${formatearDia(hoyDelNegocio(), conAnio: false)}',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: Medidas.espacio),
            if (sinCatalogo)
              const Aviso(texto: 'Necesitas conexión una vez para cargar los medios de pago.')
            else ...[
              CampoPrecio(
                controller: _monto,
                etiqueta: 'Monto',
                autofocus: true,
                errorText: _errorMonto,
                alCambiar: (_) => setState(() => _errorMonto = null),
              ),
              if (saldo > Monto.cero)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _monto.text = textoEditable(saldo);
                      _errorMonto = null;
                    }),
                    child: Text('Saldo completo (${saldo.formatear()})'),
                  ),
                ),
              const SizedBox(height: Medidas.espacio),
              Text('¿Cómo pagó?', style: tema.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final OrigenPago origen in origenes.value ?? const [])
                    ChoiceChip(
                      label: Text(origen.nombre),
                      labelStyle: const TextStyle(fontSize: Medidas.textoCuerpo),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      selected: _origenId == origen.id,
                      onSelected: (_) => setState(() {
                        _origenId = origen.id;
                        _errorOrigen = null;
                      }),
                    ),
                ],
              ),
              if (_errorOrigen != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _errorOrigen!,
                    style: tema.textTheme.bodySmall?.copyWith(color: Colores.rojo),
                  ),
                ),
              const SizedBox(height: Medidas.espacio),
              Text('Tipo', style: tema.textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<TipoPago>(
                segments: [
                  for (final tipo in TipoPago.values)
                    ButtonSegment(value: tipo, label: Text(tipo.etiqueta)),
                ],
                selected: {_tipo},
                onSelectionChanged: (seleccion) => setState(() => _tipo = seleccion.first),
              ),
              const SizedBox(height: Medidas.espacio),
              FilledButton(
                onPressed: _guardando ? null : _registrar,
                child: const Text('Registrar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
