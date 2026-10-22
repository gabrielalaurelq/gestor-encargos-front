import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/monto.dart';

/// "20" en vez de "20.00": se edita más fácil y es lo que el usuario teclea.
String textoEditable(Monto? monto) {
  if (monto == null) return '';
  final decimales = monto.centimos % 100;
  return decimales == 0
      ? '${monto.centimos ~/ 100}'
      : '${monto.centimos ~/ 100}.${decimales.toString().padLeft(2, '0')}';
}

/// Campo de soles, igual en el catálogo y en los trabajos.
class CampoPrecio extends StatelessWidget {
  const CampoPrecio({
    super.key,
    required this.controller,
    this.errorText,
    this.autofocus = false,
    this.alEnviar,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool autofocus;
  final VoidCallback? alEnviar;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      // Sin signo ni comas: la coma es separador de miles en el formato
      // peruano (S/ 1,234.50) y aquí sería ambigua.
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      textInputAction: TextInputAction.done,
      onSubmitted: alEnviar == null ? null : (_) => alEnviar!(),
      decoration: InputDecoration(
        labelText: 'Precio',
        prefixText: 'S/ ',
        hintText: '0.00',
        errorText: errorText,
      ),
    );
  }
}
