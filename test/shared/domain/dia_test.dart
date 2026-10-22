import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/domain/dia.dart';

void main() {
  test('una fecha de hecho AAAA-MM-DD es ese día, sin correrse por la zona', () {
    expect(diaDesdeIso('2026-10-24'), DateTime.utc(2026, 10, 24));
  });

  test('un instante cuenta en el día de Lima (UTC-5), como el backend', () {
    expect(diaDelNegocio('2026-10-22T04:59:00.000Z'), DateTime.utc(2026, 10, 21));
    expect(diaDelNegocio('2026-10-22T05:00:00.000Z'), DateTime.utc(2026, 10, 22));
  });
}
