import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';

final _invalido = throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'MONTO_INVALIDO'));

void main() {
  group('Monto.desde — mismas reglas que el backend', () {
    test('número del JSON y texto tecleado dan lo mismo', () {
      expect(Monto.desde(20.5), Monto.desde('20.50'));
      expect(Monto.desde(20.5).centimos, 2050);
      expect(Monto.desde(100).centimos, 10000);
    });

    test('un tercer decimal se rechaza, no se redondea', () {
      expect(() => Monto.desde('1.234'), _invalido);
      expect(() => Monto.desde(1.234), _invalido);
    });

    test('el error binario de un double se rechaza en vez de arrastrarse', () {
      expect(() => Monto.desde(0.1 + 0.2), _invalido);
    });

    test('hasta 8 dígitos enteros (DECIMAL(10,2) del Doc 4)', () {
      expect(Monto.desde('99999999.99').centimos, 9999999999);
      expect(() => Monto.desde('100000000'), _invalido);
    });

    test('acepta negativos: un saldo a favor del cliente (Doc 2)', () {
      expect(Monto.desde(-30).esNegativo, isTrue);
    });

    test('rechaza lo que no es número', () {
      expect(() => Monto.desde('abc'), _invalido);
      expect(() => Monto.desde(double.nan), _invalido);
      expect(() => Monto.desde(true), _invalido);
    });
  });

  test('suma exacta en céntimos: 0.10 + 0.20 = 0.30', () {
    expect(Monto.desde('0.10') + Monto.desde('0.20'), Monto.desde('0.30'));
  });

  test('soles para el JSON', () {
    expect(Monto.desde('20.50').soles, 20.5);
  });

  group('formatear — formato peruano', () {
    test('coma de miles, punto decimal', () {
      expect(Monto.desde('1234.5').formatear(), 'S/ 1,234.50');
      expect(Monto.desde('1234567').formatear(), 'S/ 1,234,567.00');
      expect(Monto.cero.formatear(), 'S/ 0.00');
    });

    test('negativo con el signo delante', () {
      expect(Monto.desde('-30').formatear(), '-S/ 30.00');
    });
  });
}
