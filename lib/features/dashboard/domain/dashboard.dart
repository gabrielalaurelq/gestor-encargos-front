import '../../../shared/domain/monto.dart';
import '../../encargos/domain/fila_encargo.dart';

/// Los números de arriba del Dashboard (PRD módulo 7, decisiones del
/// usuario en el S5a).
class ResumenDashboard {
  const ResumenDashboard({required this.activos, required this.saldoPendiente});

  /// Ingresado, En proceso, Listo y Pausado: un pausado sigue siendo un
  /// compromiso (P2, misma regla que el backend).
  final int activos;

  /// Lo que deben todos los no cancelados, **entregados fiados incluidos**;
  /// solo saldos positivos: uno a favor no resta (P1, PRD v1.3).
  final Monto saldoPendiente;
}

/// Las dos listas del día. Un encargo está en una sola: su entrega es hoy
/// o ya pasó.
class PendientesDelDia {
  const PendientesDelDia({required this.atrasados, required this.entregasHoy});

  /// Del más antiguo al más reciente, sin límite (PRD módulo 7).
  final List<FilaEncargo> atrasados;

  /// Los no cerrados con entrega acordada hoy; lo ya entregado hoy no está:
  /// es una lista de pendientes.
  final List<FilaEncargo> entregasHoy;
}
