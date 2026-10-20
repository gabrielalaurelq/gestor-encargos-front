import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/domain/telefono.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';

final _invalido = throwsA(
  isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'TELEFONO_INVALIDO'),
);

void main() {
  group('Telefono.peruano — el modo por defecto (PRD módulo 1)', () {
    test('9 dígitos → E.164 con +51, que es lo que acepta el backend', () {
      expect(Telefono.peruano('987654321').valor, '+51987654321');
    });

    test('tolera espacios y guiones de quien dicta el número', () {
      expect(Telefono.peruano('987 654-321').valor, '+51987654321');
    });

    test('rechaza lo que no es un celular peruano', () {
      expect(() => Telefono.peruano('87654321'), _invalido); // 8 dígitos
      expect(() => Telefono.peruano('887654321'), _invalido); // no empieza en 9
      expect(() => Telefono.peruano('+51987654321'), _invalido); // ya trae país
    });
  });

  group('Telefono.e164 — modo internacional y lo que llega de la API', () {
    test('acepta un número de otro país', () {
      expect(Telefono.e164('+34 612 345 678').valor, '+34612345678');
    });

    test('exige el + y el código de país', () {
      expect(() => Telefono.e164('612345678'), _invalido);
      expect(() => Telefono.e164('+0123456789'), _invalido);
    });
  });

  test('dígitos sin + para el enlace de WhatsApp (Doc 10)', () {
    expect(Telefono.peruano('987654321').digitos, '51987654321');
  });

  test('formato legible: agrupado para Perú, tal cual para el resto', () {
    expect(Telefono.peruano('987654321').formatear(), '987 654 321');
    expect(Telefono.e164('+34612345678').formatear(), '+34612345678');
  });

  test('igualdad por valor, venga del modo que venga', () {
    expect(Telefono.peruano('987654321'), Telefono.e164('+51987654321'));
  });
}
