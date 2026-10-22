import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/presentation/formato_fecha.dart';

void main() {
  final viernes = DateTime.utc(2026, 10, 23);

  test('corto, en español y con año por defecto', () {
    expect(formatearDia(viernes), '23 oct 2026');
  });

  test('con día de la semana y sin año, para fechas de entrega', () {
    expect(formatearDia(viernes, conDiaSemana: true, conAnio: false), 'vie 23 oct');
    expect(formatearDia(DateTime.utc(2026, 11, 1), conDiaSemana: true), 'dom 1 nov 2026');
  });
}
