import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/encargos/domain/fila_encargo.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';

FilaEncargo fila({
  String estado = 'EN_PROCESO',
  DateTime? acordada,
  DateTime? listo,
  int saldo = 0,
}) => FilaEncargo(
  id: 'e1',
  numero: 1,
  descripcion: 'x',
  codigoEstado: estado,
  fechaEntregaAcordada: acordada ?? DateTime.utc(2026, 10, 22),
  fechaListo: listo,
  fechaEntregaReal: null,
  saldoPendiente: Monto.desdeCentimos(saldo),
  creadoEn: '2026-10-01T15:00:00.000Z',
);

void main() {
  final hoy = DateTime.utc(2026, 10, 23);

  group('atrasado (Doc 2, regla 6)', () {
    test('acordada ya pasó y sin listo: sí, también pausado', () {
      expect(fila().atrasadoEl(hoy), isTrue);
      expect(fila(estado: 'PAUSADO').atrasadoEl(hoy), isTrue);
    });

    test('hoy todavía no; listo ya no; cancelado nunca', () {
      expect(fila(acordada: hoy).atrasadoEl(hoy), isFalse);
      expect(fila(listo: DateTime.utc(2026, 10, 21)).atrasadoEl(hoy), isFalse);
      expect(fila(estado: 'CANCELADO').atrasadoEl(hoy), isFalse);
    });
  });

  test('debe: saldo positivo y no cancelado; un entregado fiado sí debe (PRD v1.3)', () {
    expect(fila(saldo: 3000).debe, isTrue);
    expect(fila(estado: 'ENTREGADO', saldo: 3000).debe, isTrue);
    expect(fila(estado: 'CANCELADO', saldo: 3000).debe, isFalse);
    expect(fila(saldo: -500).debe, isFalse, reason: 'saldo a favor');
    expect(fila().debe, isFalse);
  });
}
