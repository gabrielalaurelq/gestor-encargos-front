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
import '../application/dashboard.dart';
import '../domain/dashboard.dart';

/// Dashboard (PRD módulo 7; Doc 6, wireframe): la foto del día. Arriba el
/// negocio y la fecha; tres números (activos, entregas de hoy, saldo
/// pendiente); "Atrasados" en rojo antes que "Entregas de hoy"; y el + para
/// crear un encargo. Todo sale de Drift, sin red.
///
/// "Hoy" se recalcula al volver a la app: si quedó abierta pasada la
/// medianoche, las listas cambian de día solas.
class PantallaDashboard extends ConsumerStatefulWidget {
  const PantallaDashboard({super.key});

  @override
  ConsumerState<PantallaDashboard> createState() => _EstadoPantallaDashboard();
}

class _EstadoPantallaDashboard extends ConsumerState<PantallaDashboard> {
  late final _ciclo = AppLifecycleListener(onResume: () => setState(() {}));
  final _entregasHoy = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ciclo; // se crea ya, para escuchar desde el inicio
  }

  @override
  void dispose() {
    _ciclo.dispose();
    super.dispose();
  }

  void _abrir(FilaEncargo encargo) => context.push(Rutas.encargo(encargo.id));

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final hoy = hoyDelNegocio();
    final nombre = ref.watch(nombreNegocioProvider).value;
    final resumen = ref.watch(resumenDashboardProvider);
    final pendientes = ref.watch(pendientesDelDiaProvider(hoy));

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nombre ?? 'Inicio', maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              'Hoy, ${formatearDiaLargo(hoy)}',
              style: tema.textTheme.bodyMedium?.copyWith(color: Colores.textoSecundario),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // ver PantallaClientes
        tooltip: 'Nuevo encargo',
        onPressed: () => context.push(Rutas.nuevoEncargo),
        child: const Icon(Icons.add, size: 32),
      ),
      body: switch ((resumen, pendientes)) {
        (
          AsyncValue(:final ResumenDashboard value),
          AsyncValue(value: final PendientesDelDia dia),
        ) =>
          _contenido(context, value, dia, hoy),
        (AsyncError(), _) || (_, AsyncError()) => MensajePantalla.error(
          texto: 'No se pudo mostrar el resumen del día.',
          alReintentar: () => ref
            ..invalidate(resumenDashboardProvider)
            ..invalidate(pendientesDelDiaProvider(hoy)),
        ),
        // La base local responde al instante (Doc 6: "Cargando" casi no se ve).
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _contenido(
    BuildContext context,
    ResumenDashboard resumen,
    PendientesDelDia dia,
    DateTime hoy,
  ) {
    final nada =
        resumen.activos == 0 &&
        resumen.saldoPendiente == Monto.cero &&
        dia.atrasados.isEmpty &&
        dia.entregasHoy.isEmpty;
    if (nada) {
      return const MensajePantalla(
        icono: Icons.assignment_outlined,
        texto: 'Aún no tienes encargos pendientes. Toca + para crear uno.',
      );
    }
    return ListView(
      // Abajo, espacio para que el + no tape la última tarjeta.
      padding: const EdgeInsets.fromLTRB(Medidas.espacio, Medidas.espacio, Medidas.espacio, 96),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Recuadro(valor: '${resumen.activos}', etiqueta: 'Encargos activos'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Recuadro(valor: '${dia.entregasHoy.length}', etiqueta: 'Entregas hoy'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Recuadro(
                valor: resumen.saldoPendiente.formatear(),
                etiqueta: 'Saldo pendiente',
              ),
            ),
          ],
        ),
        if (dia.atrasados.isNotEmpty) ...[
          const SizedBox(height: Medidas.espacio * 1.5),
          const _Titulo(
            icono: Icons.warning_amber_rounded,
            texto: 'Atrasados',
            color: Colores.rojo,
          ),
          for (final encargo in dia.atrasados)
            _Tarjeta(encargo: encargo, atrasadoDesde: hoy, alTocar: () => _abrir(encargo)),
        ],
        const SizedBox(height: Medidas.espacio * 1.5),
        _Titulo(key: _entregasHoy, icono: Icons.event_outlined, texto: 'Entregas de hoy'),
        if (dia.entregasHoy.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nada pendiente para hoy.'),
          )
        else
          for (final encargo in dia.entregasHoy)
            _Tarjeta(encargo: encargo, alTocar: () => _abrir(encargo)),
      ],
    );
  }
}

class _Recuadro extends StatelessWidget {
  const _Recuadro({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Column(
          children: [
            // Un saldo de cuatro cifras no cabe a 360dp con letra grande:
            // se achica antes que cortarse.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(valor, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),
            Text(
              etiqueta,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colores.textoSecundario, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({super.key, required this.icono, required this.texto, this.color});

  final IconData icono;
  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icono, color: color, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              texto,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un encargo del día: quién, qué y, si está atrasado, desde cuándo (con
/// borde rojo, Doc 6). Si no, su estado. Un toque lleva al Detalle.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.encargo, required this.alTocar, this.atrasadoDesde});

  final FilaEncargo encargo;
  final VoidCallback alTocar;

  /// Hoy, si la tarjeta es de un atrasado.
  final DateTime? atrasadoDesde;

  String get _titulo =>
      encargo.clienteNombre ??
      (encargo.numero == null ? 'Encargo sin número aún' : 'Encargo #${encargo.numero}');

  String get _detalle {
    final hoy = atrasadoDesde;
    if (hoy == null) return encargo.descripcion;
    final dias = hoy.difference(encargo.fechaEntregaAcordada).inDays;
    return '${encargo.descripcion} · debía estar listo '
        '${dias == 1 ? 'ayer' : 'hace $dias días'}';
  }

  @override
  Widget build(BuildContext context) {
    final atrasado = atrasadoDesde != null;
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
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _detalle,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colores.textoSecundario),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (atrasado)
                const Icon(Icons.chevron_right, color: Colores.textoTerciario)
              else
                EtiquetaEstado(codigo: encargo.codigoEstado),
            ],
          ),
        ),
      ),
    );
  }
}
