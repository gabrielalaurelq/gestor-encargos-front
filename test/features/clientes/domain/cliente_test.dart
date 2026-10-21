import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/clientes/domain/cliente.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';

Matcher rechazaCon(String codigo) =>
    throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', codigo));

void main() {
  test('nombre sin espacios sobrantes; vacío → CLIENTE_NOMBRE_VACIO', () {
    expect(Cliente.validarNombre(' Ana '), 'Ana');
    expect(() => Cliente.validarNombre('  '), rechazaCon('CLIENTE_NOMBRE_VACIO'));
  });

  group('teléfono tecleado', () {
    test('vacío = sin teléfono (es opcional, PRD módulo 1)', () {
      expect(Cliente.leerTelefono(' ', internacional: false), isNull);
    });

    test('modo por defecto: 9 dígitos peruanos, sin escribir +51', () {
      expect(Cliente.leerTelefono('987 654 321', internacional: false)!.valor, '+51987654321');
    });

    test('modo por defecto rechaza un número que no es celular peruano', () {
      expect(
        () => Cliente.leerTelefono('12345', internacional: false),
        rechazaCon('TELEFONO_INVALIDO'),
      );
    });

    test('modo internacional: número completo con código de país', () {
      expect(Cliente.leerTelefono('+34 612 345 678', internacional: true)!.valor, '+34612345678');
    });
  });
}
