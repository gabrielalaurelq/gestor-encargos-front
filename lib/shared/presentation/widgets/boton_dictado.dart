import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../infrastructure/dictado.dart';
import '../../infrastructure/providers.dart';
import '../tema/colores.dart';

part 'boton_dictado.g.dart';

/// Sin permiso o sin reconocedor, el micrófono se oculta en todos los campos
/// hasta que se vuelva a abrir la app (decisión del usuario, P3).
@Riverpod(keepAlive: true)
class DictadoOculto extends _$DictadoOculto {
  @override
  bool build() => false;

  void ocultar() => state = true;
}

/// El micrófono de un campo de texto (PRD módulo 8), para su `suffixIcon`.
/// Lo dictado se **agrega al final** de lo ya escrito (decisión P2: nunca
/// borra nada) y aparece mientras se habla. No guarda ni envía nada: el
/// usuario revisa y sigue. El teclado siempre sigue disponible.
class BotonDictado extends ConsumerStatefulWidget {
  const BotonDictado({super.key, required this.controller});

  final TextEditingController controller;

  @override
  ConsumerState<BotonDictado> createState() => _EstadoBotonDictado();
}

class _EstadoBotonDictado extends ConsumerState<BotonDictado> {
  late final Dictado _dictado = ref.read(dictadoProvider);
  bool _escuchando = false;

  /// Lo que había en el campo al empezar a escuchar.
  String _base = '';

  @override
  void dispose() {
    // Primero se apaga la marca: detener avisa el fin al instante, y aquí ya
    // no hay a quién redibujar.
    if (_escuchando) {
      _escuchando = false;
      _dictado.detener();
    }
    super.dispose();
  }

  Future<void> _alternar() async {
    if (_escuchando) return _dictado.detener();
    final preparacion = await _dictado.preparar();
    if (!mounted) return;
    switch (preparacion) {
      case PreparacionDictado.sinPermiso:
        return _ocultar('Sin permiso para el micrófono. Puedes seguir escribiendo.');
      case PreparacionDictado.noDisponible:
        return _ocultar(
          'El dictado por voz no está disponible en este teléfono. Puedes seguir escribiendo.',
        );
      case PreparacionDictado.listo:
        _base = widget.controller.text.trimRight();
        setState(() => _escuchando = true);
        await _dictado.escuchar(alReconocer: _poner, alTerminar: _alTerminar);
    }
  }

  void _poner(String reconocido) {
    final texto = reconocido.trim();
    if (!mounted || texto.isEmpty) return;
    // Android suele entregarlo en minúscula; un campo vacío empieza con
    // mayúscula, como al escribir.
    final nuevo = _base.isEmpty ? texto[0].toUpperCase() + texto.substring(1) : '$_base $texto';
    widget.controller.value = TextEditingValue(
      text: nuevo,
      selection: TextSelection.collapsed(offset: nuevo.length),
    );
  }

  void _alTerminar() {
    if (mounted && _escuchando) setState(() => _escuchando = false);
  }

  /// Un diálogo y no un SnackBar: muchos de estos campos están en hojas
  /// modales, que taparían el aviso de abajo.
  Future<void> _ocultar(String motivo) async {
    final oculto = ref.read(dictadoOcultoProvider.notifier);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(motivo),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
        ],
      ),
    );
    oculto.ocultar();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(dictadoOcultoProvider)) return const SizedBox.shrink();
    if (!_escuchando) {
      return IconButton(tooltip: 'Dictar', onPressed: _alternar, icon: const Icon(Icons.mic_none));
    }
    // Con letra muy grande el texto no cabe junto al campo: queda el ícono
    // rojo, y el lector de pantalla igual anuncia "Escuchando".
    final conTexto = MediaQuery.textScalerOf(context).scale(1) <= 1.3;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          label: conTexto ? null : 'Escuchando',
          child: conTexto
              ? const Text(
                  'Escuchando…',
                  style: TextStyle(color: Colores.rojo, fontWeight: FontWeight.w600),
                )
              : const SizedBox.shrink(),
        ),
        IconButton(
          tooltip: 'Dejar de dictar',
          onPressed: _alternar,
          icon: const Icon(Icons.stop_circle_outlined, color: Colores.rojo),
        ),
      ],
    );
  }
}
