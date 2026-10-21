import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/domain/texto_busqueda.dart';

void main() {
  test('minúsculas, sin tildes y la ñ como n', () {
    expect(normalizarBusqueda('María Núñez'), 'maria nunez');
    expect(normalizarBusqueda('ÁNGEL Güemes'), 'angel guemes');
  });

  test('espacios de más se colapsan y se recortan', () {
    expect(normalizarBusqueda('  Ana   Pérez '), 'ana perez');
  });

  test('lo demás queda igual (dígitos, signos)', () {
    expect(normalizarBusqueda('Taller #3 - 50%'), 'taller #3 - 50%');
  });
}
