import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/encargos/domain/estado_encargo.dart';
import 'package:gestor_encargos/features/encargos/domain/pago.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';

void main() {
  test('tipo propuesto: Adelanto antes de LISTO, Pago desde LISTO (decisión del usuario)', () {
    expect(
      {for (final estado in EstadoEncargo.values) estado: TipoPago.propuestoPara(estado)},
      {
        EstadoEncargo.ingresado: TipoPago.adelanto,
        EstadoEncargo.enProceso: TipoPago.adelanto,
        EstadoEncargo.pausado: TipoPago.adelanto,
        EstadoEncargo.listo: TipoPago.pago,
        EstadoEncargo.entregado: TipoPago.pago,
        EstadoEncargo.cancelado: TipoPago.adelanto,
      },
    );
    expect(TipoPago.propuestoPara(null), TipoPago.adelanto);
  });

  group('monto', () {
    final invalido = throwsA(
      isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'PAGO_MONTO_INVALIDO'),
    );

    test('se lee lo tecleado', () {
      expect(ReglasPago.leerMonto(' 25.5 '), Monto.desde(25.5));
    });

    test('vacío, cero o negativo no (Doc 4: CHECK monto > 0)', () {
      expect(() => ReglasPago.leerMonto(''), invalido);
      expect(() => ReglasPago.leerMonto('0'), invalido);
      expect(() => ReglasPago.validarMonto(Monto.desde(-1)), invalido);
    });
  });
}
