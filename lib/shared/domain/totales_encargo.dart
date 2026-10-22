import 'monto.dart';

/// Los tres campos calculados del encargo (Doc 2, invariantes 1-3), con la
/// **misma regla que el backend** (`Encargo.recalcular()`), para que el total
/// y el saldo que se ven sin conexión no "salten" al sincronizar:
///
/// - Si la suma de trabajos baja por debajo del descuento, el descuento se
///   ajusta a la suma (el total nunca queda negativo).
/// - `precio_total` = suma de trabajos − descuento.
/// - `saldo_pendiente` = `precio_total` − suma de pagos; puede quedar negativo
///   (saldo a favor del cliente).
class TotalesEncargo {
  const TotalesEncargo({
    required this.precioTotal,
    required this.descuento,
    required this.saldoPendiente,
  });

  factory TotalesEncargo.calcular({
    required Monto sumaTrabajos,
    required Monto descuento,
    required Monto sumaPagos,
  }) {
    final vigente = descuento > sumaTrabajos ? sumaTrabajos : descuento;
    final total = sumaTrabajos - vigente;
    return TotalesEncargo(
      precioTotal: total,
      descuento: vigente,
      saldoPendiente: total - sumaPagos,
    );
  }

  final Monto precioTotal;
  final Monto descuento;
  final Monto saldoPendiente;
}
