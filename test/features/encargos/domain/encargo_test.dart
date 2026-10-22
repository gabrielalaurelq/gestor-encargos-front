import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/encargos/domain/encargo.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';

final hoy = DateTime.utc(2026, 10, 22);

Encargo encargo({
  String estado = 'EN_PROCESO',
  DateTime? acordada,
  DateTime? prometida,
  DateTime? listo,
}) => Encargo(
  id: 'e1',
  numero: 1,
  cliente: null,
  descripcion: 'x',
  codigoEstado: estado,
  precioTotal: Monto.cero,
  descuento: Monto.cero,
  saldoPendiente: Monto.cero,
  ubicacionFisica: null,
  notasGenerales: null,
  fechaEntregaPrometida: prometida ?? acordada ?? hoy,
  fechaEntregaAcordada: acordada ?? hoy,
  fechaListo: listo,
  fechaEntregaReal: null,
);

void main() {
  final ayer = hoy.subtract(const Duration(days: 1));

  group('atrasado (Doc 2, regla 6)', () {
    test('fecha acordada pasada y sin "listo"', () {
      expect(encargo(acordada: ayer).atrasadoEl(hoy), isTrue);
    });

    test('la entrega de hoy todavía no está atrasada', () {
      expect(encargo(acordada: hoy).atrasadoEl(hoy), isFalse);
    });

    test('en cuanto está listo deja de estarlo', () {
      expect(encargo(acordada: ayer, listo: hoy).atrasadoEl(hoy), isFalse);
    });

    test('un cancelado no cuenta (decisión del usuario)', () {
      expect(encargo(acordada: ayer, estado: 'CANCELADO').atrasadoEl(hoy), isFalse);
    });
  });

  test('reprogramado: la acordada ya no es la prometida', () {
    expect(encargo(acordada: hoy).reprogramado, isFalse);
    expect(encargo(acordada: hoy, prometida: ayer).reprogramado, isTrue);
  });
}
