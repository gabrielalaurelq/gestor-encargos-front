import '../../../shared/domain/monto.dart';
import 'estado_encargo.dart';

/// Doc 2, regla 6: la fecha acordada ya pasó y no está listo. Un cancelado
/// no cuenta (decisión del usuario): ya no se va a entregar. Una sola regla
/// para el Detalle, la ficha y el Dashboard.
bool estaAtrasado({
  required EstadoEncargo? estado,
  required DateTime? fechaListo,
  required DateTime fechaEntregaAcordada,
  required DateTime hoy,
}) => estado != EstadoEncargo.cancelado && fechaListo == null && fechaEntregaAcordada.isBefore(hoy);

/// Un encargo como renglón de una lista (ficha del cliente, Dashboard, y las
/// listas que vengan): solo lo que se muestra. Solo lectura; el agregado
/// completo es [Encargo]. Reemplaza al modelo propio que tenía la ficha
/// (deuda del Sprint 1, pagada en el S5a).
class FilaEncargo {
  const FilaEncargo({
    required this.id,
    required this.numero,
    this.clienteNombre,
    required this.descripcion,
    required this.codigoEstado,
    required this.fechaEntregaAcordada,
    required this.fechaListo,
    required this.fechaEntregaReal,
    required this.saldoPendiente,
    required this.creadoEn,
  });

  final String id;

  /// `null` mientras no tiene número asignado (Doc 3, ADR-008).
  final int? numero;

  /// `null` si la lista ya es de un cliente, o si su cliente todavía no está
  /// en el teléfono.
  final String? clienteNombre;
  final String descripcion;
  final String codigoEstado;

  // Días del negocio (ver `dia.dart`).
  final DateTime fechaEntregaAcordada;
  final DateTime? fechaListo;
  final DateTime? fechaEntregaReal;

  /// Negativo = saldo a favor del cliente (Doc 2).
  final Monto saldoPendiente;

  /// Instante ISO del alta: desempata el orden.
  final String creadoEn;

  EstadoEncargo? get estado => EstadoEncargo.desde(codigoEstado);

  bool atrasadoEl(DateTime hoy) => estaAtrasado(
    estado: estado,
    fechaListo: fechaListo,
    fechaEntregaAcordada: fechaEntregaAcordada,
    hoy: hoy,
  );

  /// Le falta cobrar. Un cancelado no se cobra: su saldo no es una deuda; un
  /// entregado fiado sí (decisión del usuario, PRD v1.3).
  bool get debe => estado != EstadoEncargo.cancelado && saldoPendiente > Monto.cero;
}
