import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/monto.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/campo_precio.dart';
import '../application/catalogo.dart';
import '../domain/servicio.dart';

/// Lo que pasó en la hoja, para que la pantalla confirme (y ofrezca deshacer).
enum AccionServicio { creado, precioCambiado, desactivado, reactivado }

/// Hoja inferior para crear un servicio o editar uno existente: solo dos
/// campos (PRD módulo 4, flujo 3b). Al editar, el nombre no se toca (Doc 5).
class HojaServicio extends ConsumerStatefulWidget {
  const HojaServicio({super.key, this.servicio});

  /// `null` = servicio nuevo.
  final Servicio? servicio;

  static Future<AccionServicio?> abrir(BuildContext context, {Servicio? servicio}) =>
      showModalBottomSheet<AccionServicio>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => HojaServicio(servicio: servicio),
      );

  @override
  ConsumerState<HojaServicio> createState() => _EstadoHojaServicio();
}

class _EstadoHojaServicio extends ConsumerState<HojaServicio> {
  late final _nombre = TextEditingController();
  late final _precio = TextEditingController(text: textoEditable(_servicio?.precio));
  String? _errorNombre;
  String? _errorPrecio;
  bool _guardando = false;

  Servicio? get _servicio => widget.servicio;

  @override
  void dispose() {
    _nombre.dispose();
    _precio.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<AccionServicio?> Function() accion) async {
    if (_guardando) return;
    setState(() {
      _guardando = true;
      _errorNombre = null;
      _errorPrecio = null;
    });
    try {
      final resultado = await accion();
      if (mounted) Navigator.pop(context, resultado);
    } on ValorInvalido catch (error) {
      setState(() {
        if (error.codigo == 'SERVICIO_NOMBRE_VACIO') {
          _errorNombre = error.mensaje;
        } else {
          _errorPrecio = error.mensaje;
        }
      });
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Valida los dos campos antes de escribir nada, para mostrar ambos errores
  /// a la vez en lugar de uno por intento.
  Future<void> _guardar() async {
    final servicio = _servicio;
    String? nombre;
    Monto? precio;
    String? errorNombre;
    String? errorPrecio;
    if (servicio == null) {
      try {
        nombre = Servicio.validarNombre(_nombre.text);
      } on ValorInvalido catch (error) {
        errorNombre = error.mensaje;
      }
    }
    try {
      precio = Servicio.leerPrecio(_precio.text);
    } on ValorInvalido catch (error) {
      errorPrecio = error.mensaje;
    }
    if (errorNombre != null || errorPrecio != null) {
      setState(() {
        _errorNombre = errorNombre;
        _errorPrecio = errorPrecio;
      });
      return;
    }

    final repositorio = ref.read(repositorioServiciosProvider);
    await _ejecutar(() async {
      if (servicio == null) {
        await repositorio.crear(nombre: nombre!, precio: precio!);
        return AccionServicio.creado;
      }
      if (precio == servicio.precio) return null;
      await repositorio.cambiarPrecio(servicio.id, precio!);
      return AccionServicio.precioCambiado;
    });
  }

  Future<AccionServicio> _alternarActivo() async {
    final servicio = _servicio!;
    await ref
        .read(repositorioServiciosProvider)
        .cambiarActivo(servicio.id, activo: !servicio.activo);
    return servicio.activo ? AccionServicio.desactivado : AccionServicio.reactivado;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final servicio = _servicio;
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
            Text(servicio?.nombre ?? 'Nuevo servicio', style: tema.textTheme.titleLarge),
            if (servicio != null) ...[
              const SizedBox(height: 4),
              Text(
                'Para cambiar el nombre, desactívalo y crea uno nuevo.',
                style: tema.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: Medidas.espacio),
            if (servicio == null) ...[
              TextField(
                controller: _nombre,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ej. Basta de jean',
                  errorText: _errorNombre,
                ),
              ),
              const SizedBox(height: Medidas.espacio),
            ],
            CampoPrecio(
              controller: _precio,
              autofocus: servicio != null,
              alEnviar: _guardar,
              errorText: _errorPrecio,
            ),
            const SizedBox(height: Medidas.espacio),
            FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar')),
            if (servicio != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _guardando ? null : () => _ejecutar(_alternarActivo),
                child: Text(servicio.activo ? 'Desactivar' : 'Reactivar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
