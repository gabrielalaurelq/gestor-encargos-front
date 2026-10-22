import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/domain/dia.dart';

void main() {
  test('una fecha de hecho AAAA-MM-DD es ese día, sin correrse por la zona', () {
    expect(diaDesdeIso('2026-10-24'), DateTime.utc(2026, 10, 24));
  });

  test('y vuelve a AAAA-MM-DD para la API, con ceros', () {
    expect(isoDesdeDia(DateTime.utc(2026, 3, 5)), '2026-03-05');
  });

  test('un instante cuenta en el día de Lima (UTC-5), como el backend', () {
    expect(diaDelNegocio('2026-10-22T04:59:00.000Z'), DateTime.utc(2026, 10, 21));
    expect(diaDelNegocio('2026-10-22T05:00:00.000Z'), DateTime.utc(2026, 10, 22));
  });

  test('hoy es el día de Lima del reloj del teléfono', () {
    expect(hoyDelNegocio(DateTime.utc(2026, 10, 23, 3)), DateTime.utc(2026, 10, 22));
  });
}
