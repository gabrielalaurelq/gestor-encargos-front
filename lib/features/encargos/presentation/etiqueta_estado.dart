import 'package:flutter/material.dart';

import '../../../shared/presentation/tema/colores.dart';
import '../domain/estado_encargo.dart';

/// El estado de un encargo como etiqueta: siempre con su nombre escrito, el
/// color solo acompaña (Doc 6: nunca información solo por color). Verde =
/// listo para entregar, ámbar = en curso o detenido, neutro = sin acción
/// pendiente. El rojo queda reservado para "atrasado" (Dashboard).
class EtiquetaEstado extends StatelessWidget {
  const EtiquetaEstado({super.key, required this.codigo});

  /// El código tal como está guardado; uno desconocido se muestra tal cual.
  final String codigo;

  @override
  Widget build(BuildContext context) {
    final estado = EstadoEncargo.desde(codigo);
    final (texto, fondo) = switch (estado) {
      EstadoEncargo.listo => (Colores.verde, Colores.verdeFondo),
      EstadoEncargo.enProceso || EstadoEncargo.pausado => (Colores.ambar, Colores.ambarFondo),
      _ => (Colores.textoSecundario, Colores.fondo),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(8)),
      child: Text(
        estado?.etiqueta ?? codigo,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: texto),
      ),
    );
  }
}
