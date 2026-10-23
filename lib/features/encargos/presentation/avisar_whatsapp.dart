import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/infrastructure/providers.dart';
import '../../clientes/presentation/hoja_cliente.dart';
import '../application/encargos.dart';
import 'mensaje_whatsapp.dart';

/// "Avisar por WhatsApp" (PRD módulo 9): abre WhatsApp con el mensaje del
/// estado actual; el envío lo hace el negociante allá. Lee el encargo al
/// momento de tocar, no el que se pintó: desde el aviso "Ahora: Listo" ya
/// tiene que salir el mensaje de Listo.
///
/// Sin teléfono (opcional desde el PRD v1.2), lo explica y ofrece agregarlo
/// en la misma hoja de edición del cliente; al guardarlo, sigue a WhatsApp
/// (decisión del usuario, P2).
Future<void> avisarPorWhatsapp(BuildContext context, WidgetRef ref, String encargoId) async {
  var encargo = ref.read(encargoProvider(encargoId)).value;
  final cliente = encargo?.cliente;
  if (encargo == null || cliente == null) return;
  var telefono = cliente.telefono;
  if (telefono == null) {
    final agregar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${cliente.nombre} no tiene teléfono'),
        content: const Text('Agrégalo para poder avisarle por WhatsApp.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agregar teléfono'),
          ),
        ],
      ),
    );
    if (agregar != true || !context.mounted) return;
    final resultado = await HojaCliente.abrir(context, cliente: cliente);
    telefono = resultado?.cliente.telefono;
    if (telefono == null || !context.mounted) return;
    // Con el nombre como haya quedado tras editar.
    encargo = ref.read(encargoProvider(encargoId)).value ?? encargo;
  }
  final abierto = await ref
      .read(abridorEnlacesProvider)
      .abrir(enlaceWhatsapp(telefono, mensajeWhatsapp(encargo)));
  if (!abierto && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('No se pudo abrir WhatsApp.')));
  }
}
