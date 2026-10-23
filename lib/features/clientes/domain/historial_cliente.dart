import '../../../shared/domain/dia.dart';
import '../../../shared/domain/monto.dart';
import '../../encargos/domain/fila_encargo.dart';

/// Un encargo tal como se lista en la ficha del cliente (PRD módulo 1): la
/// [FilaEncargo] común más lo pagado, para el resumen.
class EncargoDeCliente extends FilaEncargo {
  const EncargoDeCliente({
    required super.id,
    required super.numero,
    required super.descripcion,
    required super.codigoEstado,
    required super.fechaEntregaAcordada,
    required super.fechaListo,
    required super.fechaEntregaReal,
    required super.saldoPendiente,
    required this.pagado,
    required super.creadoEn,
  });

  /// Suma de sus pagos, cualquiera sea el estado del encargo.
  final Monto pagado;
}

/// Resumen del historial (PRD módulo 18), con las mismas reglas que
/// `GET /clientes/{id}` en el backend: cuenta **todos** los encargos
/// (activos, entregados y cancelados), suma **todos** sus pagos —también los
/// de cancelados, igual que la Caja diaria— y la última visita es el alta
/// del encargo más reciente.
class ResumenCliente {
  const ResumenCliente({required this.encargos, required this.pagado, required this.ultimaVisita});

  /// Se calcula sobre la misma lista que se muestra debajo: no pueden
  /// contradecirse.
  factory ResumenCliente.de(List<EncargoDeCliente> encargos) {
    var pagado = Monto.cero;
    String? ultimo;
    for (final e in encargos) {
      pagado += e.pagado;
      if (ultimo == null || DateTime.parse(e.creadoEn).isAfter(DateTime.parse(ultimo))) {
        ultimo = e.creadoEn;
      }
    }
    return ResumenCliente(
      encargos: encargos.length,
      pagado: pagado,
      ultimaVisita: ultimo == null ? null : diaDelNegocio(ultimo),
    );
  }

  final int encargos;
  final Monto pagado;

  /// Día del negocio; `null` sin encargos.
  final DateTime? ultimaVisita;
}
