import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/monto.dart';
import '../../../shared/domain/texto_busqueda.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/campo_precio.dart';
import '../../servicios/application/catalogo.dart';
import '../../servicios/domain/servicio.dart';
import '../application/encargos.dart';
import '../domain/objeto_recibido.dart';
import '../domain/trabajo.dart';
import 'selector_objeto.dart';

enum _Via { catalogo, personalizado }

/// "Agregar trabajo" (PRD módulo 4): del catálogo, con un toque, o
/// personalizado, con descripción y precio libres. Abre en "Del catálogo"
/// cuando hay servicios activos. Si el encargo tiene objetos, primero se
/// elige para cuál es (S3d2); por defecto, ninguno.
class HojaAgregarTrabajo extends ConsumerStatefulWidget {
  const HojaAgregarTrabajo({super.key, required this.encargoId});

  final String encargoId;

  /// `true` si se agregó.
  static Future<bool?> abrir(BuildContext context, String encargoId) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => HojaAgregarTrabajo(encargoId: encargoId),
  );

  @override
  ConsumerState<HojaAgregarTrabajo> createState() => _EstadoHojaAgregarTrabajo();
}

class _EstadoHojaAgregarTrabajo extends ConsumerState<HojaAgregarTrabajo> {
  _Via? _elegida;
  String? _objetoId;
  final _busqueda = TextEditingController();
  final _descripcion = TextEditingController();
  final _precio = TextEditingController();
  String? _errorDescripcion;
  String? _errorPrecio;
  String? _errorCatalogo;
  bool _guardando = false;

  @override
  void dispose() {
    _busqueda.dispose();
    _descripcion.dispose();
    _precio.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<void> Function() accion, void Function(String) alError) async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      await accion();
      if (mounted) Navigator.pop(context, true);
    } on ValorInvalido catch (error) {
      setState(() => alError(error.mensaje));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _agregarDelCatalogo(Servicio servicio) => _ejecutar(
    () => ref
        .read(repositorioTrabajosProvider)
        .agregarDelCatalogo(widget.encargoId, servicio, objetoId: _objetoId),
    (mensaje) => _errorCatalogo = mensaje,
  );

  /// Valida los dos campos antes de escribir, para mostrar ambos errores a la
  /// vez.
  Future<void> _agregarPersonalizado() async {
    String? descripcion;
    Monto? precio;
    String? errorDescripcion;
    String? errorPrecio;
    try {
      descripcion = ReglasTrabajo.validarDescripcion(_descripcion.text);
    } on ValorInvalido catch (error) {
      errorDescripcion = error.mensaje;
    }
    try {
      precio = ReglasTrabajo.leerPrecio(_precio.text);
    } on ValorInvalido catch (error) {
      errorPrecio = error.mensaje;
    }
    setState(() {
      _errorDescripcion = errorDescripcion;
      _errorPrecio = errorPrecio;
    });
    if (descripcion == null || precio == null) return;
    await _ejecutar(
      () => ref
          .read(repositorioTrabajosProvider)
          .agregarPersonalizado(
            widget.encargoId,
            descripcion: descripcion!,
            precio: precio!,
            objetoId: _objetoId,
          ),
      (mensaje) => _errorDescripcion = mensaje,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final activos = [
      for (final servicio in ref.watch(catalogoProvider).value ?? const <Servicio>[])
        if (servicio.activo) servicio,
    ];
    final via = _elegida ?? (activos.isEmpty ? _Via.personalizado : _Via.catalogo);
    final objetos = ref.watch(objetosProvider(widget.encargoId)).value ?? const <ObjetoRecibido>[];
    final alto = MediaQuery.sizeOf(context).height;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Medidas.espacio,
        0,
        Medidas.espacio,
        Medidas.espacio + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: alto * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Agregar trabajo', style: tema.textTheme.titleLarge),
            const SizedBox(height: Medidas.espacio),
            if (objetos.isNotEmpty) ...[
              SelectorObjeto(
                objetos: objetos,
                elegido: _objetoId,
                alElegir: _guardando ? null : (id) => setState(() => _objetoId = id),
              ),
              const SizedBox(height: Medidas.espacio),
            ],
            SegmentedButton<_Via>(
              segments: const [
                ButtonSegment(value: _Via.catalogo, label: Text('Del catálogo')),
                ButtonSegment(value: _Via.personalizado, label: Text('Personalizado')),
              ],
              selected: {via},
              showSelectedIcon: false,
              onSelectionChanged: (elegidas) => setState(() => _elegida = elegidas.single),
            ),
            const SizedBox(height: Medidas.espacio),
            if (via == _Via.catalogo)
              Flexible(child: _catalogo(context, activos))
            else
              Flexible(child: _personalizado()),
          ],
        ),
      ),
    );
  }

  Widget _catalogo(BuildContext context, List<Servicio> activos) {
    if (activos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Medidas.espacio),
        child: Text(
          'Tu catálogo no tiene servicios activos. Agrega el trabajo como personalizado.',
        ),
      );
    }
    final consulta = normalizarBusqueda(_busqueda.text);
    final visibles = [
      for (final servicio in activos)
        if (normalizarBusqueda(servicio.nombre).contains(consulta)) servicio,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _busqueda,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Buscar servicio',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        if (_errorCatalogo != null) ...[
          const SizedBox(height: 8),
          Text(_errorCatalogo!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 8),
        Flexible(
          child: visibles.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: Medidas.espacio),
                  child: Text('Ningún servicio coincide.'),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final servicio in visibles)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        minTileHeight: Medidas.toqueMinimo,
                        title: Text(servicio.nombre),
                        trailing: Text(
                          servicio.precio.formatear(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        enabled: !_guardando,
                        onTap: () => _agregarDelCatalogo(servicio),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _personalizado() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _descripcion,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Descripción',
              hintText: 'Ej. Confección de vestido',
              errorText: _errorDescripcion,
            ),
          ),
          const SizedBox(height: Medidas.espacio),
          CampoPrecio(
            controller: _precio,
            errorText: _errorPrecio,
            alEnviar: _agregarPersonalizado,
          ),
          const SizedBox(height: Medidas.espacio),
          FilledButton(
            onPressed: _guardando ? null : _agregarPersonalizado,
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }
}
