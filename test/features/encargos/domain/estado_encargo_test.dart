import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/encargos/domain/estado_encargo.dart';

void main() {
  test('los seis códigos del backend, con su nombre para el usuario', () {
    expect(
      [for (final e in EstadoEncargo.values) e.codigo],
      ['INGRESADO', 'EN_PROCESO', 'LISTO', 'ENTREGADO', 'PAUSADO', 'CANCELADO'],
    );
    expect(EstadoEncargo.desde('EN_PROCESO')!.etiqueta, 'En proceso');
  });

  test('un código desconocido no rompe: queda en null', () {
    expect(EstadoEncargo.desde('ARCHIVADO'), isNull);
  });

  test('cerrados: solo entregado y cancelado', () {
    expect(
      [
        for (final e in EstadoEncargo.values)
          if (e.cerrado) e,
      ],
      [EstadoEncargo.entregado, EstadoEncargo.cancelado],
    );
  });
}
