import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/rutas.dart';
import '../../../shared/presentation/formato_fecha.dart';
import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/mensaje_pantalla.dart';
import '../../encargos/domain/estado_encargo.dart';
import '../../encargos/presentation/etiqueta_estado.dart';
import '../application/clientes.dart';
import '../domain/cliente.dart';
import '../domain/historial_cliente.dart';
import 'hoja_cliente.dart';

/// Ficha de Cliente (Doc 6, pantalla 4; PRD módulos 1 y 18): sus datos, el
/// resumen del historial y sus encargos del más reciente al más antiguo.
/// Todo sale de la base local: se ve igual sin conexión.
class PantallaFichaCliente extends ConsumerWidget {
  const PantallaFichaCliente({super.key, required this.clienteId});

  final String clienteId;

  Future<void> _editar(BuildContext context, Cliente cliente) async {
    final resultado = await HojaCliente.abrir(context, cliente: cliente);
    if (!context.mounted) return;
    switch (resultado) {
      case ClienteGuardado():
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Cambios guardados')));
      // Ante el aviso de teléfono repetido eligió ver al otro cliente.
      case ClienteExistenteElegido(:final cliente):
        unawaited(context.push(Rutas.cliente(cliente.id)));
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cliente = ref.watch(clienteProvider(clienteId));
    return switch (cliente) {
      AsyncValue(:final Cliente value) => _Ficha(
        cliente: value,
        encargos: ref.watch(encargosDeClienteProvider(clienteId)),
        alEditar: () => _editar(context, value),
        alReintentar: () => ref.invalidate(encargosDeClienteProvider(clienteId)),
      ),
      AsyncError() => Scaffold(
        appBar: AppBar(),
        body: MensajePantalla.error(
          texto: 'No se pudo mostrar este cliente.',
          alReintentar: () => ref.invalidate(clienteProvider(clienteId)),
        ),
      ),
      // La base local responde al instante (Doc 6: "Cargando" casi no se ve).
      AsyncLoading() => Scaffold(appBar: AppBar()),
      // Un enlace a un cliente que no está en el teléfono.
      AsyncData() => Scaffold(
        appBar: AppBar(),
        body: const MensajePantalla(
          icono: Icons.person_off_outlined,
          texto: 'Este cliente no existe.',
        ),
      ),
    };
  }
}

class _Ficha extends StatelessWidget {
  const _Ficha({
    required this.cliente,
    required this.encargos,
    required this.alEditar,
    required this.alReintentar,
  });

  final Cliente cliente;
  final AsyncValue<List<EncargoDeCliente>> encargos;
  final VoidCallback alEditar;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final telefono = cliente.telefono;
    return Scaffold(
      appBar: AppBar(
        title: Text(cliente.nombre),
        actions: [
          IconButton(
            tooltip: 'Editar cliente',
            onPressed: alEditar,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null, // ver PantallaClientes
        onPressed: () => context.push(Rutas.nuevoEncargoPara(cliente.id)),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo encargo'),
      ),
      body: switch (encargos) {
        AsyncValue(:final List<EncargoDeCliente> value) => ListView(
          // Que el botón "Nuevo encargo" no tape el último encargo.
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            if (telefono != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Medidas.espacio, 0, Medidas.espacio, 8),
                child: Row(
                  children: [
                    const Icon(Icons.phone_outlined, color: Colores.textoSecundario),
                    const SizedBox(width: 8),
                    Text(telefono.formatear()),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(Medidas.espacio),
              child: _Resumen(ResumenCliente.de(value)),
            ),
            if (value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Medidas.espacio, 8, Medidas.espacio, 4),
                child: Text('Encargos', style: tema.textTheme.titleMedium),
              ),
            for (final encargo in value)
              _FilaEncargo(
                encargo: encargo,
                alTocar: () => context.push(Rutas.encargo(encargo.id)),
              ),
          ],
        ),
        AsyncError() => MensajePantalla.error(
          texto: 'No se pudieron mostrar sus encargos.',
          alReintentar: alReintentar,
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen(this.resumen);

  final ResumenCliente resumen;

  @override
  Widget build(BuildContext context) {
    final ultimaVisita = resumen.ultimaVisita;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Medidas.espacio),
        child: SizedBox(
          width: double.infinity,
          child: ultimaVisita == null
              // Sin encargos, un "0 encargos · S/ 0.00" no dice nada.
              ? const Text('Aún no tiene encargos.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${resumen.encargos == 1 ? '1 encargo' : '${resumen.encargos} encargos'}'
                      ' · ${resumen.pagado.formatear()} pagado',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text('Última visita: ${formatearDia(ultimaVisita)}'),
                  ],
                ),
        ),
      ),
    );
  }
}

class _FilaEncargo extends StatelessWidget {
  const _FilaEncargo({required this.encargo, required this.alTocar});

  final EncargoDeCliente encargo;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final estado = encargo.estado;
    final entregaReal = encargo.fechaEntregaReal;
    final detalle = [
      encargo.numero == null ? 'Sin número aún' : '#${encargo.numero}',
      if (estado == EstadoEncargo.entregado && entregaReal != null)
        'Entregado el ${formatearDia(entregaReal)}'
      else if (estado != null && !estado.cerrado)
        'Entrega: ${formatearDia(encargo.fechaEntregaAcordada, conDiaSemana: true, conAnio: false)}',
    ].join(' · ');
    final debe = encargo.debe;
    return ListTile(
      title: Text(encargo.descripcion, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(debe ? '$detalle\nDebe ${encargo.saldoPendiente.formatear()}' : detalle),
      trailing: EtiquetaEstado(codigo: encargo.codigoEstado),
      onTap: alTocar,
    );
  }
}
