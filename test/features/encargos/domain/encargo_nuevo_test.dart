import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/encargos/domain/encargo_nuevo.dart';
import 'package:gestor_encargos/shared/domain/valor_invalido.dart';

void main() {
  test('descripción sin espacios sobrantes; vacía → ENCARGO_DESCRIPCION_VACIA', () {
    expect(ReglasEncargo.validarDescripcion('  Basta  '), 'Basta');
    expect(
      () => ReglasEncargo.validarDescripcion(' '),
      throwsA(isA<ValorInvalido>().having((e) => e.codigo, 'codigo', 'ENCARGO_DESCRIPCION_VACIA')),
    );
  });
}
