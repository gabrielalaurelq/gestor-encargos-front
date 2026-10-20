import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../application/catalogo.dart';
import '../domain/servicio.dart';
import 'hoja_servicio.dart';

/// Catálogo de servicios (Doc 6, pantalla 7; PRD módulo 4, flujo 3b): la
/// lista de precios fijos del negocio. Los desactivados quedan aparte, plegados
/// y reactivables (decisión del usuario): desactivar por error se deshace.
class PantallaCatalogo extends ConsumerWidget {
  const PantallaCatalogo({super.key});

  static String confirmacion(AccionServicio accion) => switch (accion) {
    AccionServicio.creado => 'Servicio agregado',
    AccionServicio.precioCambiado => 'Precio actualizado',
    AccionServicio.desactivado => 'Servicio desactivado',
    AccionServicio.reactivado => 'Servicio reactivado',
  };

  Future<void> _abrir(BuildContext context, WidgetRef ref, {Servicio? servicio}) async {
    final accion = await HojaServicio.abrir(context, servicio: servicio);
    if (accion == null || !context.mounted) return;
    // Confirmación breve, sin modal que cerrar (Doc 6, estado "Éxito").
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(confirmacion(accion)),
          action: accion == AccionServicio.desactivado
              ? SnackBarAction(
                  label: 'Deshacer',
                  onPressed: () => ref
                      .read(repositorioServiciosProvider)
                      .cambiarActivo(servicio!.id, activo: true),
                )
              : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(catalogoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de servicios')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Agregar servicio',
        onPressed: () => _abrir(context, ref),
        child: const Icon(Icons.add, size: 32),
      ),
      body: switch (catalogo) {
        AsyncData(:final value) => _Lista(
          servicios: value,
          alTocar: (servicio) => _abrir(context, ref, servicio: servicio),
        ),
        AsyncError() => _Error(alReintentar: () => ref.invalidate(catalogoProvider)),
        // La base local responde al instante (Doc 6: "Cargando" casi no se ve).
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.servicios, required this.alTocar});

  final List<Servicio> servicios;
  final void Function(Servicio) alTocar;

  @override
  Widget build(BuildContext context) {
    final activos = [
      for (final s in servicios)
        if (s.activo) s,
    ];
    final desactivados = [
      for (final s in servicios)
        if (!s.activo) s,
    ];
    if (servicios.isEmpty) {
      return const _Mensaje(
        icono: Icons.list_alt,
        texto: 'Aún no tienes servicios. Toca + para agregar el primero.',
      );
    }
    return ListView(
      // Que el botón (+) no tape el último precio.
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (activos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(Medidas.espacio),
            child: Text('No tienes servicios activos. Toca + para agregar uno.'),
          ),
        for (final servicio in activos) _Fila(servicio: servicio, alTocar: alTocar),
        if (desactivados.isNotEmpty)
          ExpansionTile(
            title: Text('Desactivados (${desactivados.length})'),
            textColor: Colores.textoSecundario,
            collapsedTextColor: Colores.textoSecundario,
            children: [
              for (final servicio in desactivados) _Fila(servicio: servicio, alTocar: alTocar),
            ],
          ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.servicio, required this.alTocar});

  final Servicio servicio;
  final void Function(Servicio) alTocar;

  @override
  Widget build(BuildContext context) {
    final color = servicio.activo ? Colores.texto : Colores.textoSecundario;
    return ListTile(
      title: Text(servicio.nombre, style: TextStyle(color: color)),
      trailing: Text(
        servicio.precio.formatear(),
        style: TextStyle(fontSize: Medidas.textoCuerpo, fontWeight: FontWeight.w600, color: color),
      ),
      onTap: () => alTocar(servicio),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.icono, required this.texto, this.accion});

  final IconData icono;
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Medidas.espacio * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 64, color: Colores.textoTerciario),
            const SizedBox(height: Medidas.espacio),
            Text(texto, textAlign: TextAlign.center),
            if (accion != null) ...[const SizedBox(height: Medidas.espacio), accion!],
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.alReintentar});

  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    // Lenguaje humano y botón de reintentar (Doc 6, estado "Error").
    return _Mensaje(
      icono: Icons.error_outline,
      texto: 'No se pudo mostrar el catálogo.',
      accion: OutlinedButton(onPressed: alReintentar, child: const Text('Reintentar')),
    );
  }
}
