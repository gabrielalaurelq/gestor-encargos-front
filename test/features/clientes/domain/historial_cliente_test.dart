import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/clientes/domain/historial_cliente.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';

EncargoDeCliente encargo(String creadoEn, {String estado = 'ENTREGADO', int pagado = 0}) =>
    EncargoDeCliente(
      id: creadoEn,
      numero: 1,
      descripcion: 'x',
      codigoEstado: estado,
      fechaEntregaAcordada: DateTime.utc(2026, 10, 1),
      fechaListo: null,
      fechaEntregaReal: null,
      saldoPendiente: Monto.cero,
      pagado: Monto.desdeCentimos(pagado),
      creadoEn: creadoEn,
    );

void main() {
  test('sin encargos: cero y sin última visita', () {
    final resumen = ResumenCliente.de([]);

    expect([resumen.encargos, resumen.pagado, resumen.ultimaVisita], [0, Monto.cero, null]);
  });

  test('cuenta todos y suma todo lo pagado, también de cancelados (PRD 18)', () {
    final resumen = ResumenCliente.de([
      encargo('2026-10-01T15:00:00.000Z', pagado: 5000),
      encargo('2026-10-05T15:00:00.000Z', estado: 'CANCELADO', pagado: 1000),
      encargo('2026-10-03T15:00:00.000Z', estado: 'LISTO'),
    ]);

    expect(resumen.encargos, 3);
    expect(resumen.pagado, Monto.desdeCentimos(6000));
  });

  test('última visita: el alta más reciente, en el día de Lima', () {
    final resumen = ResumenCliente.de([
      encargo('2026-10-01T15:00:00.000Z'),
      // 00:30 del 6 en UTC = 19:30 del 5 en Lima.
      encargo('2026-10-06T00:30:00.000Z'),
    ]);

    expect(resumen.ultimaVisita, DateTime.utc(2026, 10, 5));
  });
}
