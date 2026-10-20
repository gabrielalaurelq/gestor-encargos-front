import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'base_datos.g.dart';

/// Pares clave-valor del propio dispositivo que no son datos del negocio: la
/// marca `since` de la última sincronización, el bloque de numeración Hi/Lo
/// reservado, etc. (los usa el motor de sync, bloque F3).
class Metadatos extends Table {
  TextColumn get clave => text()();
  TextColumn get valor => text()();

  @override
  Set<Column<Object>> get primaryKey => {clave};
}

/// La base local (Doc 3: Drift es la fuente de verdad del dispositivo). Las
/// tablas espejo de las 9 colecciones de `/sync` y la Outbox llegan en F3.
///
/// **Migraciones:** cada cambio de esquema sube [schemaVersion] y agrega su
/// paso en `onUpgrade`. Un teléfono puede saltarse varias versiones de la app
/// (Doc 0 §12.2: el público actualiza poco), así que los pasos se aplican en
/// cadena desde la versión que tenga, nunca "de la anterior a la actual". Se
/// generan con `dart run drift_dev make-migrations`, que además produce tests
/// que verifican cada paso contra el esquema real de esa versión.
@DriftDatabase(tables: [Metadatos])
class BaseDatos extends _$BaseDatos {
  BaseDatos([QueryExecutor? ejecutor]) : super(ejecutor ?? _abrir());

  static QueryExecutor _abrir() => driftDatabase(name: 'gestor_encargos');

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (_) async {
      // SQLite trae las llaves foráneas **apagadas** por defecto: sin esto,
      // las FK que declaren las tablas de F3 serían decorativas.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<String?> leerMetadato(String clave) async {
    final fila = await (select(metadatos)..where((m) => m.clave.equals(clave))).getSingleOrNull();
    return fila?.valor;
  }

  Future<void> guardarMetadato(String clave, String valor) =>
      into(metadatos).insertOnConflictUpdate(MetadatosCompanion.insert(clave: clave, valor: valor));

  Future<void> borrarMetadato(String clave) =>
      (delete(metadatos)..where((m) => m.clave.equals(clave))).go();
}
