import 'package:flutter/material.dart';

import '../../../shared/presentation/tema/tema.dart';
import '../domain/objeto_recibido.dart';

/// "¿Para qué objeto?" en las hojas de trabajo (S3d2, Caso 6): "Ninguno" o
/// uno de los objetos del encargo. Quien lo usa no lo muestra si el encargo
/// no tiene objetos.
class SelectorObjeto extends StatelessWidget {
  const SelectorObjeto({
    super.key,
    required this.objetos,
    required this.elegido,
    required this.alElegir,
  });

  final List<ObjetoRecibido> objetos;

  /// `null` es "Ninguno"; también lo es un objeto que ya no está en la lista.
  final String? elegido;
  final ValueChanged<String?>? alElegir;

  @override
  Widget build(BuildContext context) {
    final vigente = objetos.any((o) => o.id == elegido) ? elegido : null;
    Widget chip(String texto, String? id) => ChoiceChip(
      label: Text(texto),
      labelStyle: const TextStyle(fontSize: Medidas.textoCuerpo),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      selected: vigente == id,
      onSelected: alElegir == null ? null : (_) => alElegir!(id),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('¿Para qué objeto?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip('Ninguno', null),
            for (final objeto in objetos) chip(objeto.descripcion, objeto.id),
          ],
        ),
      ],
    );
  }
}
