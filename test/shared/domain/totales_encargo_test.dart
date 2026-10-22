import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/domain/totales_encargo.dart';

/// La misma regla que `Encargo.recalcular()` del backend, con los casos del
/// PRD (módulos 2, 4 y 5).
void main() {
  TotalesEncargo calcular(num trabajos, num descuento, num pagos) => TotalesEncargo.calcular(
    sumaTrabajos: Monto.desde(trabajos),
    descuento: Monto.desde(descuento),
    sumaPagos: Monto.desde(pagos),
  );

  List<String> textos(TotalesEncargo t) => [
    t.precioTotal.formatear(),
    t.descuento.formatear(),
    t.saldoPendiente.formatear(),
  ];

  test('PRD 2: trabajos S/33 con descuento S/3 → total S/30', () {
    expect(textos(calcular(33, 3, 0)), ['S/ 30.00', 'S/ 3.00', 'S/ 30.00']);
  });

  test('sin descuento el total es la suma de trabajos', () {
    expect(calcular(20.5, 0, 0).precioTotal, Monto.desde(20.5));
  });

  test('el saldo es el total menos los pagos, y puede quedar a favor del cliente', () {
    expect(calcular(30, 0, 10).saldoPendiente, Monto.desde(20));
    expect(calcular(30, 0, 35).saldoPendiente.formatear(), '-S/ 5.00');
  });

  test('PRD 4: si la suma baja del descuento, el descuento se ajusta y el total queda en 0', () {
    expect(textos(calcular(0, 3, 0)), ['S/ 0.00', 'S/ 0.00', 'S/ 0.00']);
    expect(textos(calcular(2, 3, 0)), ['S/ 0.00', 'S/ 2.00', 'S/ 0.00']);
  });

  test('céntimos exactos: 0.10 + 0.20 no arrastra error', () {
    expect(calcular(0.3, 0.1, 0.1).saldoPendiente, Monto.desde(0.1));
  });
}
