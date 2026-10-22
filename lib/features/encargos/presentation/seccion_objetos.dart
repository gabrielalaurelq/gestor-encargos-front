import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../application/encargos.dart';
import '../domain/encargo.dart';
import '../domain/estado_encargo.dart';
import '../domain/objeto_recibido.dart';
import '../domain/trabajo.dart';
import 'hoja_objeto.dart';

/// Sección "Objetos recibidos" del Detalle (PRD módulo 3), la primera de las
/// apiladas (Doc 6). Sin objetos no es un error: hay encargos sin nada que
/// dejar (Caso 3). Con el encargo entregado o cancelado se ve pero no se
/// cambia (decisión del usuario).
class SeccionObjetos extends ConsumerWidget {
  const SeccionObjetos({super.key, required this.encargo});

  final Encargo encargo;

  Future<void> _abrir(BuildContext context, {ObjetoRecibido? objeto, int trabajos = 0}) async {
    final accion = await HojaObjeto.abrir(context, encargo.id, objeto: objeto, trabajos: trabajos);
    if (accion == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (accion) {
            AccionObjeto.agregado => 'Objeto agregado',
            AccionObjeto.guardado => 'Cambios guardados',
            AccionObjeto.eliminado => 'Objeto eliminado',
          }),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final objetos = ref.watch(objetosProvider(encargo.id)).value ?? const <ObjetoRecibido>[];
    final trabajos = ref.watch(trabajosProvider(encargo.id)).value ?? const <Trabajo>[];
    final estado = encargo.estado;
    final cerrado = estado?.cerrado ?? false;
    int trabajosDe(ObjetoRecibido objeto) =>
        trabajos.where((t) => t.objetoRecibidoId == objeto.id).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Medidas.espacio),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Objetos recibidos', style: tema.textTheme.titleMedium),
            if (objetos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Ningún objeto registrado.'),
              )
            else
              for (final objeto in objetos)
                _Fila(
                  objeto: objeto,
                  trabajos: trabajosDe(objeto),
                  alTocar: cerrado
                      ? null
                      : () => _abrir(context, objeto: objeto, trabajos: trabajosDe(objeto)),
                ),
            const SizedBox(height: 8),
            if (cerrado)
              Text(
                estado == EstadoEncargo.entregado
                    ? 'Ya fue entregado: los objetos no se cambian.'
                    : 'Está cancelado: los objetos no se cambian.',
                style: tema.textTheme.bodySmall,
              )
            else
              OutlinedButton.icon(
                onPressed: () => _abrir(context),
                icon: const Icon(Icons.add),
                label: const Text('Agregar objeto'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.objeto, required this.trabajos, required this.alTocar});

  final ObjetoRecibido objeto;
  final int trabajos;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: alTocar,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Medidas.toqueMinimo),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(objeto.descripcion),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              switch (trabajos) {
                0 => 'sin trabajos',
                1 => '1 trabajo',
                _ => '$trabajos trabajos',
              },
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colores.textoTerciario),
            ),
          ],
        ),
      ),
    );
  }
}
