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

  test('las transiciones son las de la tabla del backend (estado-encargo.ts)', () {
    const backend = {
      'INGRESADO': ['EN_PROCESO', 'LISTO', 'ENTREGADO', 'PAUSADO', 'CANCELADO'],
      'EN_PROCESO': ['LISTO', 'ENTREGADO', 'PAUSADO', 'CANCELADO'],
      'LISTO': ['ENTREGADO', 'PAUSADO', 'CANCELADO'],
      'PAUSADO': ['INGRESADO', 'EN_PROCESO', 'LISTO', 'ENTREGADO', 'CANCELADO'],
      'CANCELADO': ['INGRESADO', 'EN_PROCESO', 'LISTO', 'PAUSADO'],
      'ENTREGADO': <String>[],
    };
    for (final desde in EstadoEncargo.values) {
      for (final hasta in EstadoEncargo.values) {
        expect(
          desde.puedePasarA(hasta),
          backend[desde.codigo]!.contains(hasta.codigo),
          reason: '${desde.codigo} → ${hasta.codigo}',
        );
      }
    }
  });

  test('el siguiente natural va primero', () {
    expect(EstadoEncargo.ingresado.destinos.first, EstadoEncargo.enProceso);
    expect(EstadoEncargo.enProceso.destinos.first, EstadoEncargo.listo);
    expect(EstadoEncargo.listo.destinos.first, EstadoEncargo.entregado);
  });

  test('de LISTO no se vuelve a EN PROCESO (decisión del usuario)', () {
    expect(EstadoEncargo.listo.puedePasarA(EstadoEncargo.enProceso), isFalse);
    expect(EstadoEncargo.entregado.destinos, isEmpty);
  });
}
