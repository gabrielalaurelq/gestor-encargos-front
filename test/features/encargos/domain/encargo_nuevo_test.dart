import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/encargos/domain/encargo_nuevo.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';

void main() {
  test('descripción sin espacios sobrantes; vacía → ENCARGO_DESCRIPCION_VACIA', () {
    expect(ReglasEncargo.validarDescripcion('  Basta  '), 'Basta');
    expect(
      () => ReglasEncargo.validarDescripcion(' '),
      throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'ENCARGO_DESCRIPCION_VACIA')),
    );
  });

  group('descuento (Doc 2, invariante 2)', () {
    final invalido = throwsA(
      isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'DESCUENTO_INVALIDO'),
    );

    test('vacío es S/ 0; "3.5" son S/ 3.50', () {
      expect(ReglasEncargo.leerDescuento(' '), Monto.cero);
      expect(ReglasEncargo.leerDescuento('3.5'), Monto.desde(3.5));
    });

    test('igual a la suma vale; mayor no, con el mensaje del backend', () {
      expect(ReglasEncargo.validarDescuento(Monto.desde(33), Monto.desde(33)), Monto.desde(33));
      expect(() => ReglasEncargo.validarDescuento(Monto.desde(25), Monto.desde(20)), invalido);
      try {
        ReglasEncargo.validarDescuento(Monto.desde(25), Monto.desde(20));
      } on ValorInvalido catch (error) {
        expect(error.mensaje, 'El descuento no puede ser mayor a la suma de los trabajos.');
      }
    });

    test('negativo no', () {
      expect(() => ReglasEncargo.validarDescuento(Monto.desde(-1), null), invalido);
    });
  });
}
