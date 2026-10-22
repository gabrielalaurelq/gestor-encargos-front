import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/rutas.dart';
import '../../../shared/domain/dia.dart';
import '../../../shared/domain/monto.dart';
import '../../../shared/presentation/formato_fecha.dart';
import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../../../shared/presentation/widgets/aviso.dart';
import '../../../shared/presentation/widgets/mensaje_pantalla.dart';
import '../../../shared/sync/providers.dart';
import '../application/encargos.dart';
import '../domain/encargo.dart';
import 'etiqueta_estado.dart';
import 'hoja_editar_encargo.dart';

/// Detalle de Encargo (Doc 6, pantalla 6), por ahora su cabecera: cliente,
/// descripción, entrega, ubicación, total y saldo, como en el wireframe. Las
/// secciones (Objetos, Trabajos, Pagos, Notas, Fotos) y las acciones
/// ("Cambiar estado", WhatsApp) se suman en los Sprints 3-5.
class PantallaDetalleEncargo extends ConsumerWidget {
  const PantallaDetalleEncargo({super.key, required this.encargoId});

  final String encargoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(encargoProvider(encargoId))) {
      AsyncValue(:final Encargo value) => _Detalle(
        encargo: value,
        rechazado: (ref.watch(operacionesApartadasProvider).value ?? const []).any(
          (op) => op.encargoId == encargoId || op.entidadId == encargoId,
        ),
      ),
      AsyncError() => Scaffold(
        appBar: AppBar(),
        body: MensajePantalla.error(
          texto: 'No se pudo mostrar este encargo.',
          alReintentar: () => ref.invalidate(encargoProvider(encargoId)),
        ),
      ),
      // La base local responde al instante (Doc 6: "Cargando" casi no se ve).
      AsyncLoading() => Scaffold(appBar: AppBar()),
      AsyncData() => Scaffold(
        appBar: AppBar(),
        body: const MensajePantalla(
          icono: Icons.assignment_late_outlined,
          texto: 'Este encargo no existe.',
        ),
      ),
    };
  }
}

class _Detalle extends StatelessWidget {
  const _Detalle({required this.encargo, required this.rechazado});

  final Encargo encargo;

  /// Tiene un cambio que el servidor rechazó (Doc 7 v1.2).
  final bool rechazado;

  Future<void> _editar(BuildContext context) async {
    final guardado = await HojaEditarEncargo.abrir(context, encargo);
    if (guardado != true || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Cambios guardados')));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final hoy = hoyDelNegocio();
    final numero = encargo.numero;
    final notas = encargo.notasGenerales;
    return Scaffold(
      appBar: AppBar(
        title: Text(numero == null ? 'Encargo · sin número aún' : 'Encargo #$numero'),
        actions: [
          IconButton(
            tooltip: 'Editar encargo',
            onPressed: () => _editar(context),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Medidas.espacio),
        children: [
          // En el wireframe va en la barra; con el lápiz al lado, el número
          // quedaba sin espacio en un teléfono de 360dp (y con letra grande).
          Align(
            alignment: Alignment.centerLeft,
            child: EtiquetaEstado(codigo: encargo.codigoEstado),
          ),
          const SizedBox(height: 12),
          if (rechazado) ...[
            Aviso(
              texto: 'Un cambio de este encargo no se guardó.',
              accion: OutlinedButton(
                onPressed: () => context.push(Rutas.cambiosNoGuardados),
                child: const Text('Ver'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Medidas.espacio,
                4,
                Medidas.espacio,
                Medidas.espacio,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Cliente(encargo: encargo),
                  Text(encargo.descripcion, style: tema.textTheme.bodyLarge),
                  const Divider(height: Medidas.espacio * 2),
                  _Datos(encargo: encargo, hoy: hoy),
                ],
              ),
            ),
          ),
          if (notas != null && notas.trim().isNotEmpty) ...[
            const SizedBox(height: Medidas.espacio),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Medidas.espacio),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notas generales', style: tema.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(notas),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tocar el nombre lleva a su ficha (decisión de diseño del S2b).
class _Cliente extends StatelessWidget {
  const _Cliente({required this.encargo});

  final Encargo encargo;

  @override
  Widget build(BuildContext context) {
    final cliente = encargo.cliente;
    if (cliente == null) return const SizedBox(height: 8);
    final telefono = cliente.telefono;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(cliente.nombre, style: Theme.of(context).textTheme.titleMedium),
      subtitle: telefono == null ? null : Text(telefono.formatear()),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Rutas.cliente(cliente.id)),
    );
  }
}

class _Datos extends StatelessWidget {
  const _Datos({required this.encargo, required this.hoy});

  final Encargo encargo;
  final DateTime hoy;

  String _dia(DateTime dia) => formatearDia(dia, conDiaSemana: true, conAnio: dia.year != hoy.year);

  @override
  Widget build(BuildContext context) {
    final atrasado = encargo.atrasadoEl(hoy);
    final saldo = encargo.saldoPendiente;
    final ubicacion = encargo.ubicacionFisica?.trim() ?? '';
    final listo = encargo.fechaListo;
    final entregado = encargo.fechaEntregaReal;

    final entrega = _Dato(
      etiqueta: 'Entrega',
      valor: _dia(encargo.fechaEntregaAcordada),
      color: atrasado ? Colores.rojo : null,
      notas: [
        if (atrasado)
          const Text(
            'Atrasado',
            style: TextStyle(color: Colores.rojo, fontWeight: FontWeight.w700),
          ),
        if (encargo.reprogramado)
          Text(
            'Prometido: ${_dia(encargo.fechaEntregaPrometida)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
    final lugar = ubicacion.isEmpty
        ? const _Dato(etiqueta: 'Ubicación', valor: 'Sin ubicación', color: Colores.textoTerciario)
        : _Dato(etiqueta: 'Ubicación', valor: ubicacion);
    final total = _Dato(etiqueta: 'Precio total', valor: encargo.precioTotal.formatear());
    final pendiente = saldo.esNegativo
        ? _Dato(etiqueta: 'A favor del cliente', valor: (Monto.cero - saldo).formatear())
        : _Dato(
            etiqueta: 'Saldo pendiente',
            valor: saldo.formatear(),
            // Doc 6: el saldo se resalta en rojo cuando es mayor a S/ 0.
            color: saldo.centimos > 0 ? Colores.rojo : null,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Par(entrega, lugar),
        const SizedBox(height: 12),
        _Par(total, pendiente),
        if (encargo.descuento.centimos > 0 || listo != null || entregado != null) ...[
          const SizedBox(height: 12),
          _Par(
            encargo.descuento.centimos > 0
                ? _Dato(etiqueta: 'Descuento', valor: encargo.descuento.formatear())
                : null,
            switch ((listo, entregado)) {
              (_, final DateTime dia) => _Dato(etiqueta: 'Entregado el', valor: _dia(dia)),
              (final DateTime dia, null) => _Dato(etiqueta: 'Listo el', valor: _dia(dia)),
              _ => null,
            },
          ),
        ],
      ],
    );
  }
}

class _Par extends StatelessWidget {
  const _Par(this.izquierda, this.derecha);

  final Widget? izquierda;
  final Widget? derecha;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: izquierda ?? const SizedBox.shrink()),
        const SizedBox(width: 12),
        Expanded(child: derecha ?? const SizedBox.shrink()),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor, this.color, this.notas = const []});

  final String etiqueta;
  final String valor;
  final Color? color;
  final List<Widget> notas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
        Text(
          valor,
          style: TextStyle(
            fontSize: Medidas.textoCuerpo,
            fontWeight: FontWeight.w600,
            color: color ?? Colores.texto,
          ),
        ),
        ...notas,
      ],
    );
  }
}
