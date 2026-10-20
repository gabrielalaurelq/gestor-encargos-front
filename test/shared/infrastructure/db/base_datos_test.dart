import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';

/// Contra SQLite en memoria (Doc 7, Bloque 4: los tests de integración usan
/// Drift en memoria, no el backend).
void main() {
  late BaseDatos base;

  setUp(() => base = BaseDatos(NativeDatabase.memory()));
  tearDown(() => base.close());

  test('las llaves foráneas están encendidas (SQLite las trae apagadas)', () async {
    final fila = await base.customSelect('PRAGMA foreign_keys').getSingle();

    expect(fila.read<int>('foreign_keys'), 1);
  });

  group('metadatos', () {
    test('sin valor → null', () async {
      expect(await base.leerMetadato('sync.since'), isNull);
    });

    test('guardar dos veces la misma clave la reemplaza', () async {
      await base.guardarMetadato('sync.since', '2026-10-20T10:00:00.000Z');
      await base.guardarMetadato('sync.since', '2026-10-20T11:00:00.000Z');

      expect(await base.leerMetadato('sync.since'), '2026-10-20T11:00:00.000Z');
    });

    test('borrar', () async {
      await base.guardarMetadato('x', '1');
      await base.borrarMetadato('x');

      expect(await base.leerMetadato('x'), isNull);
    });
  });
}
