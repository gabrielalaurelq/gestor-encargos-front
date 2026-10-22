import 'package:flutter/material.dart';

import '../tema/colores.dart';
import '../tema/tema.dart';

/// Advertencia que no bloquea (Doc 6: ámbar = advertencia): explica algo
/// raro y deja seguir. Lo usan el teléfono repetido y la fecha ya pasada.
class Aviso extends StatelessWidget {
  const Aviso({super.key, required this.texto, this.accion});

  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colores.ambarFondo,
        borderRadius: BorderRadius.circular(Medidas.radio),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(texto),
            if (accion != null) ...[const SizedBox(height: 8), accion!],
          ],
        ),
      ),
    );
  }
}
