import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/servicios/domain/servicio.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';

Matcher rechazaCon(String codigo) =>
    throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', codigo));

/// Mismas reglas y códigos que el backend (`servicio.ts`).
void main() {
  group('nombre', () {
    test('se guarda sin espacios sobrantes', () {
      expect(Servicio.validarNombre('  Basta de jean '), 'Basta de jean');
    });

    test('vacío o solo espacios → SERVICIO_NOMBRE_VACIO', () {
      expect(() => Servicio.validarNombre('   '), rechazaCon('SERVICIO_NOMBRE_VACIO'));
    });
  });

  group('precio tecleado', () {
    test('entero o con hasta 2 decimales', () {
      expect(Servicio.leerPrecio('20'), Monto.desdeCentimos(2000));
      expect(Servicio.leerPrecio('12.5'), Monto.desdeCentimos(1250));
    });

    test('cero vale: un retoque de garantía (PRD módulo 4)', () {
      expect(Servicio.leerPrecio('0'), Monto.cero);
    });

    test('vacío → SERVICIO_PRECIO_INVALIDO, con un mensaje que dice qué hacer', () {
      expect(() => Servicio.leerPrecio(' '), rechazaCon('SERVICIO_PRECIO_INVALIDO'));
    });

    test('negativo → SERVICIO_PRECIO_INVALIDO', () {
      expect(() => Servicio.leerPrecio('-5'), rechazaCon('SERVICIO_PRECIO_INVALIDO'));
    });

    test('un tercer decimal se rechaza, no se redondea (Doc 5, MONTO_INVALIDO)', () {
      expect(() => Servicio.leerPrecio('9.999'), rechazaCon('MONTO_INVALIDO'));
    });
  });
}
