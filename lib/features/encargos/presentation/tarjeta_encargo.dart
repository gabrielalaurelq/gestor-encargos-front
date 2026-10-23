import 'package:flutter/material.dart';

import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../domain/fila_encargo.dart';

/// "debía estar listo ayer" / "debía estar listo hace 3 días".
String textoAtraso(FilaEncargo encargo, DateTime hoy) {
  final dias = hoy.difference(encargo.fechaEntregaAcordada).inDays;
  return 'debía estar listo ${dias == 1 ? 'ayer' : 'hace $dias días'}';
}

/// Un encargo como tarjeta de lista (Dashboard y sus listas, S5a-S5b): quién,
/// qué y lo que diga [detalle]; a la derecha, [lateral]. Un atrasado lleva
/// el borde rojo del wireframe (Doc 6). Un toque lleva al Detalle.
class TarjetaEncargo extends StatelessWidget {
  const TarjetaEncargo({
    super.key,
    required this.encargo,
    required this.detalle,
    required this.lateral,
    required this.alTocar,
    this.atrasado = false,
  });

  final FilaEncargo encargo;
  final String detalle;
  final Widget lateral;
  final VoidCallback alTocar;
  final bool atrasado;

  String get _titulo =>
      encargo.clienteNombre ??
      (encargo.numero == null ? 'Encargo sin número aún' : 'Encargo #${encargo.numero}');

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.radio),
        side: const BorderSide(color: Colores.borde),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alTocar,
        child: Container(
          constraints: const BoxConstraints(minHeight: Medidas.toqueMinimo),
          decoration: atrasado
              ? const BoxDecoration(
                  border: Border(left: BorderSide(color: Colores.rojo, width: 6)),
                )
              : null,
          padding: const EdgeInsets.symmetric(horizontal: Medidas.espacio, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titulo,
                      style: tema.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalle,
                      style: tema.textTheme.bodyMedium?.copyWith(color: Colores.textoSecundario),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              lateral,
            ],
          ),
        ),
      ),
    );
  }
}
