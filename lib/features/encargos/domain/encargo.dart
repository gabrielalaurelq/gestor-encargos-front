import '../../../shared/domain/monto.dart';
import '../../clientes/domain/cliente.dart';
import 'estado_encargo.dart';
import 'fila_encargo.dart';

/// Los datos generales de un encargo para su detalle (PRD módulo 2; Doc 6,
/// pantalla 6). Solo lectura: las secciones (objetos, trabajos, pagos…) se
/// suman en los Sprints 3-4.
class Encargo {
  const Encargo({
    required this.id,
    required this.numero,
    required this.cliente,
    required this.descripcion,
    required this.codigoEstado,
    required this.precioTotal,
    required this.descuento,
    required this.saldoPendiente,
    required this.ubicacionFisica,
    required this.notasGenerales,
    required this.fechaEntregaPrometida,
    required this.fechaEntregaAcordada,
    required this.fechaListo,
    required this.fechaEntregaReal,
  });

  final String id;

  /// `null` mientras no tiene número asignado (Doc 3, ADR-008).
  final int? numero;

  /// `null` solo si su cliente todavía no está en el teléfono.
  final Cliente? cliente;
  final String descripcion;
  final String codigoEstado;
  final Monto precioTotal;
  final Monto descuento;

  /// Negativo = saldo a favor del cliente (Doc 2).
  final Monto saldoPendiente;
  final String? ubicacionFisica;
  final String? notasGenerales;

  // Días del negocio (ver `dia.dart`).
  final DateTime fechaEntregaPrometida;
  final DateTime fechaEntregaAcordada;
  final DateTime? fechaListo;
  final DateTime? fechaEntregaReal;

  EstadoEncargo? get estado => EstadoEncargo.desde(codigoEstado);

  /// Se reprogramó: la primera promesa queda fija (PRD módulo 2).
  bool get reprogramado => fechaEntregaPrometida != fechaEntregaAcordada;

  /// Ver [estaAtrasado].
  bool atrasadoEl(DateTime hoy) => estaAtrasado(
    estado: estado,
    fechaListo: fechaListo,
    fechaEntregaAcordada: fechaEntregaAcordada,
    hoy: hoy,
  );
}
