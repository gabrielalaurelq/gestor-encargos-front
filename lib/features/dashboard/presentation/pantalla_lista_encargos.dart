import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/rutas.dart';
import '../../../shared/domain/dia.dart';
import '../../../shared/domain/monto.dart';
import '../../../shared/presentation/formato_fecha.dart';
import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/mensaje_pantalla.dart';
import '../../encargos/domain/fila_encargo.dart';
import '../../encargos/presentation/etiqueta_estado.dart';
import '../../encargos/presentation/tarjeta_encargo.dart';
import '../application/dashboard.dart';
import '../domain/dashboard.dart';

/// La lista detrás de un número del Dashboard (S5b, opción a: una sola
/// pantalla con filtro). "Encargos activos" va por fecha de entrega, con los
/// atrasados marcados; "Saldo pendiente", de la deuda mayor a la menor. La
/// Búsqueda (Sprint 7) puede ser esta misma pantalla con otro filtro.
class PantallaListaEncargos extends ConsumerWidget {
  const PantallaListaEncargos({super.key, required this.filtro});

  final FiltroEncargos filtro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoy = hoyDelNegocio();
    return Scaffold(
      appBar: AppBar(title: Text(filtro.titulo)),
      body: switch (ref.watch(listaEncargosProvider(filtro))) {
        AsyncValue(:final List<FilaEncargo> value) when value.isEmpty => MensajePantalla(
          icono: filtro == FiltroEncargos.activos
              ? Icons.assignment_turned_in_outlined
              : Icons.savings_outlined,
          texto: filtro == FiltroEncargos.activos
              ? 'No hay encargos activos.'
              : 'Nadie te debe nada.',
        ),
        AsyncValue(:final List<FilaEncargo> value) => ListView(
          padding: const EdgeInsets.all(Medidas.espacio),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _resumen(value),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colores.textoSecundario),
              ),
            ),
            for (final encargo in value) _fila(context, encargo, hoy),
          ],
        ),
        AsyncError() => MensajePantalla.error(
          texto: 'No se pudo mostrar la lista.',
          alReintentar: () => ref.invalidate(listaEncargosProvider(filtro)),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  String _resumen(List<FilaEncargo> encargos) {
    final cuantos = encargos.length == 1 ? '1 encargo' : '${encargos.length} encargos';
    if (filtro == FiltroEncargos.activos) return cuantos;
    final total = encargos.fold(Monto.cero, (suma, e) => suma + e.saldoPendiente);
    return '$cuantos · deben ${total.formatear()} en total';
  }

  Widget _fila(BuildContext context, FilaEncargo encargo, DateTime hoy) {
    void abrir() => context.push(Rutas.encargo(encargo.id));
    switch (filtro) {
      case FiltroEncargos.activos:
        final atrasado = encargo.atrasadoEl(hoy);
        final cuando = atrasado
            ? textoAtraso(encargo, hoy)
            : 'Entrega: ${formatearDia(encargo.fechaEntregaAcordada, conDiaSemana: true, conAnio: encargo.fechaEntregaAcordada.year != hoy.year)}';
        return TarjetaEncargo(
          encargo: encargo,
          detalle: '${encargo.descripcion}\n$cuando',
          atrasado: atrasado,
          lateral: EtiquetaEstado(codigo: encargo.codigoEstado),
          alTocar: abrir,
        );
      case FiltroEncargos.conSaldo:
        return TarjetaEncargo(
          encargo: encargo,
          detalle: '${encargo.descripcion}\n${encargo.estado?.etiqueta ?? encargo.codigoEstado}',
          lateral: Text(
            encargo.saldoPendiente.formatear(),
            style: const TextStyle(
              fontSize: Medidas.textoCuerpo,
              fontWeight: FontWeight.w700,
              color: Colores.rojo,
            ),
          ),
          alTocar: abrir,
        );
    }
  }
}
