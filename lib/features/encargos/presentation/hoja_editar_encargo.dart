import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/dia.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/presentation/formato_fecha.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/aviso.dart';
import '../application/encargos.dart';
import '../domain/encargo.dart';
import '../domain/estado_encargo.dart';
import 'selector_fecha_entrega.dart';

/// "Editar encargo" (S2c; decisión del usuario: una sola hoja): descripción,
/// reprogramar, ubicación física y notas generales. El cliente no se cambia
/// (el contrato no lo acepta) y el descuento llega en el S3b2.
class HojaEditarEncargo extends ConsumerStatefulWidget {
  const HojaEditarEncargo({super.key, required this.encargo});

  final Encargo encargo;

  /// `true` si se guardó algún cambio.
  static Future<bool?> abrir(BuildContext context, Encargo encargo) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => HojaEditarEncargo(encargo: encargo),
  );

  @override
  ConsumerState<HojaEditarEncargo> createState() => _EstadoHojaEditarEncargo();
}

class _EstadoHojaEditarEncargo extends ConsumerState<HojaEditarEncargo> {
  late final TextEditingController _descripcion;
  late final TextEditingController _ubicacion;
  late final TextEditingController _notas;
  late DateTime _fecha;
  String? _errorDescripcion;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final encargo = widget.encargo;
    _descripcion = TextEditingController(text: encargo.descripcion);
    _ubicacion = TextEditingController(text: encargo.ubicacionFisica ?? '');
    _notas = TextEditingController(text: encargo.notasGenerales ?? '');
    _fecha = encargo.fechaEntregaAcordada;
  }

  @override
  void dispose() {
    _descripcion.dispose();
    _ubicacion.dispose();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      final guardado = await ref
          .read(repositorioEncargosProvider)
          .editar(
            widget.encargo,
            descripcion: _descripcion.text,
            fechaEntregaAcordada: _fecha,
            ubicacion: _ubicacion.text,
            notas: _notas.text,
          );
      if (mounted) Navigator.pop(context, guardado);
    } on ValorInvalido catch (error) {
      setState(() => _errorDescripcion = error.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final encargo = widget.encargo;
    final hoy = hoyDelNegocio();
    final reprograma = _fecha != encargo.fechaEntregaAcordada;
    final pasada = reprograma && _fecha.isBefore(hoy);
    String dia(DateTime d) => formatearDia(d, conDiaSemana: true, conAnio: d.year != hoy.year);

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
            Text('Editar encargo', style: tema.textTheme.titleLarge),
            const SizedBox(height: Medidas.espacio),
            TextField(
              controller: _descripcion,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: '¿Qué hay que hacer?',
                errorText: _errorDescripcion,
              ),
            ),
            const SizedBox(height: Medidas.espacio),
            // Decisión del usuario: entregado o cancelado no se reprograma.
            if (encargo.estado?.cerrado ?? false)
              _FechaFija(
                fecha: dia(encargo.fechaEntregaAcordada),
                motivo: encargo.estado == EstadoEncargo.entregado
                    ? 'Ya fue entregado: la fecha no se cambia.'
                    : 'Está cancelado: la fecha no se cambia.',
              )
            else ...[
              SelectorFechaEntrega(
                fecha: _fecha,
                hoy: hoy,
                alCambiar: (nueva) => setState(() => _fecha = nueva),
              ),
              if (reprograma) ...[
                const SizedBox(height: 8),
                Text(
                  'La primera promesa (${dia(encargo.fechaEntregaPrometida)}) queda guardada.',
                  style: tema.textTheme.bodySmall,
                ),
              ],
              if (pasada) ...[
                const SizedBox(height: 8),
                const Aviso(texto: 'Esa fecha ya pasó. ¿Es correcta?'),
              ],
            ],
            const SizedBox(height: Medidas.espacio),
            TextField(
              controller: _ubicacion,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Ubicación (opcional)',
                hintText: 'Ej. cajón 3, bolsa 12',
              ),
            ),
            const SizedBox(height: Medidas.espacio),
            TextField(
              controller: _notas,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notas generales (opcional)'),
            ),
            const SizedBox(height: Medidas.espacio),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: Text(pasada ? 'Guardar igual' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FechaFija extends StatelessWidget {
  const _FechaFija({required this.fecha, required this.motivo});

  final String fecha;
  final String motivo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fecha de entrega', style: tema.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(fecha),
        Text(motivo, style: tema.textTheme.bodySmall),
      ],
    );
  }
}
