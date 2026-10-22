import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/dia.dart';
import '../../../shared/domain/monto.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/presentation/formato_fecha.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/aviso.dart';
import '../../../shared/presentation/widgets/campo_precio.dart';
import '../application/encargos.dart';
import '../domain/encargo.dart';
import '../domain/encargo_nuevo.dart';
import '../domain/estado_encargo.dart';
import '../domain/trabajo.dart';
import 'selector_fecha_entrega.dart';

/// "Editar encargo" (S2c; decisión del usuario: una sola hoja): descripción,
/// reprogramar, descuento (S3b2), ubicación física y notas generales. El
/// cliente no se cambia (el contrato no lo acepta).
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
  late final TextEditingController _descuento;
  late DateTime _fecha;
  String? _errorDescripcion;
  String? _errorDescuento;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final encargo = widget.encargo;
    _descripcion = TextEditingController(text: encargo.descripcion);
    _ubicacion = TextEditingController(text: encargo.ubicacionFisica ?? '');
    _notas = TextEditingController(text: encargo.notasGenerales ?? '');
    _descuento = TextEditingController(
      text: encargo.descuento.esCero ? '' : textoEditable(encargo.descuento),
    );
    _fecha = encargo.fechaEntregaAcordada;
  }

  @override
  void dispose() {
    _descripcion.dispose();
    _ubicacion.dispose();
    _notas.dispose();
    _descuento.dispose();
    super.dispose();
  }

  /// El descuento solo se edita con el encargo abierto y con trabajos
  /// (decisiones del usuario); si no, no se envía.
  bool _descuentoEditable(Monto sumaTrabajos) =>
      !(widget.encargo.estado?.cerrado ?? false) && sumaTrabajos > Monto.cero;

  Future<void> _guardar(Monto sumaTrabajos) async {
    if (_guardando) return;
    Monto? descuento;
    if (_descuentoEditable(sumaTrabajos)) {
      try {
        descuento = ReglasEncargo.validarDescuento(
          ReglasEncargo.leerDescuento(_descuento.text),
          sumaTrabajos,
        );
      } on ValorInvalido catch (error) {
        setState(() => _errorDescuento = error.mensaje);
        return;
      }
    }
    setState(() {
      _guardando = true;
      _errorDescripcion = null;
      _errorDescuento = null;
    });
    try {
      final guardado = await ref
          .read(repositorioEncargosProvider)
          .editar(
            widget.encargo,
            descripcion: _descripcion.text,
            fechaEntregaAcordada: _fecha,
            ubicacion: _ubicacion.text,
            notas: _notas.text,
            descuento: descuento,
          );
      if (mounted) Navigator.pop(context, guardado);
    } on ValorInvalido catch (error) {
      setState(() {
        if (error.codigo == 'DESCUENTO_INVALIDO' || error.codigo == 'MONTO_INVALIDO') {
          _errorDescuento = error.mensaje;
        } else {
          _errorDescripcion = error.mensaje;
        }
      });
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// "Suma de trabajos: S/ 33.00 · Total: S/ 30.00", al ritmo de lo que se
  /// escribe.
  String _ayudaDescuento(Monto suma) {
    final base = 'Suma de trabajos: ${suma.formatear()}';
    try {
      final descuento = ReglasEncargo.leerDescuento(_descuento.text);
      return descuento > suma ? base : '$base · Total: ${(suma - descuento).formatear()}';
    } on ValorInvalido {
      return base;
    }
  }

  /// Un descuento mayor que la suma se marca al instante, sin esperar a
  /// "Guardar".
  String? _excesoDescuento(Monto suma) {
    try {
      ReglasEncargo.validarDescuento(ReglasEncargo.leerDescuento(_descuento.text), suma);
      return null;
    } on ValorInvalido catch (error) {
      return error.codigo == 'DESCUENTO_INVALIDO' ? error.mensaje : null;
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
    final trabajos = ref.watch(trabajosProvider(encargo.id)).value ?? const <Trabajo>[];
    final suma = trabajos.fold(Monto.cero, (total, t) => total + t.precio);
    final cerrado = encargo.estado?.cerrado ?? false;
    final motivoCerrado = encargo.estado == EstadoEncargo.entregado
        ? 'Ya fue entregado'
        : 'Está cancelado';

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
            if (cerrado)
              _DatoFijo(
                titulo: 'Fecha de entrega',
                valor: dia(encargo.fechaEntregaAcordada),
                motivo: '$motivoCerrado: la fecha no se cambia.',
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
            if (cerrado)
              _DatoFijo(
                titulo: 'Descuento',
                valor: encargo.descuento.esCero ? 'Sin descuento' : encargo.descuento.formatear(),
                motivo: '$motivoCerrado: el descuento no se cambia.',
              )
            else if (!_descuentoEditable(suma))
              Text(
                'Agrega trabajos para poder aplicar un descuento.',
                style: tema.textTheme.bodySmall,
              )
            else
              CampoPrecio(
                controller: _descuento,
                etiqueta: 'Descuento (opcional)',
                ayuda: _ayudaDescuento(suma),
                errorText: _errorDescuento ?? _excesoDescuento(suma),
                alCambiar: (_) => setState(() => _errorDescuento = null),
              ),
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
              onPressed: _guardando ? null : () => _guardar(suma),
              child: Text(pasada ? 'Guardar igual' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatoFijo extends StatelessWidget {
  const _DatoFijo({required this.titulo, required this.valor, required this.motivo});

  final String titulo;
  final String valor;
  final String motivo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: tema.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(valor),
        Text(motivo, style: tema.textTheme.bodySmall),
      ],
    );
  }
}
