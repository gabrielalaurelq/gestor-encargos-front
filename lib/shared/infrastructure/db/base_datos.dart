import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tablas.dart';

export 'tablas.dart';

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

/// La base local (Doc 3: Drift es la fuente de verdad del dispositivo): las
/// tablas espejo de las 9 colecciones de `/sync` (`tablas.dart`), el catálogo
/// de orígenes de pago y las tablas propias del dispositivo: la Outbox y los
/// metadatos.
///
/// **Esquema editable hasta el primer release.** Mientras ningún teléfono
/// tenga la app instalada, el esquema se cambia en el lugar y [schemaVersion]
/// sigue en 1: no hay base vieja que migrar. Desde el primer build publicado en
/// Google Play, cada cambio es una versión nueva.
///
/// **Migraciones:** cada cambio de esquema sube [schemaVersion] y agrega su
/// paso en `onUpgrade`. Un teléfono puede saltarse varias versiones de la app
/// (Doc 0 §12.2: el público actualiza poco), así que los pasos se aplican en
/// cadena desde la versión que tenga, nunca "de la anterior a la actual". Se
/// generan con `dart run drift_dev make-migrations`, que además produce tests
/// que verifican cada paso contra el esquema real de esa versión.
@DriftDatabase(
  tables: [
    Metadatos,
    Clientes,
    Servicios,
    Encargos,
    ObjetosRecibidos,
    Trabajos,
    Materiales,
    Pagos,
    Notas,
    Fotos,
    OrigenesPago,
    OperacionesOutbox,
  ],
)
class BaseDatos extends _$BaseDatos {
  BaseDatos([QueryExecutor? ejecutor]) : super(ejecutor ?? _abrir());

  static QueryExecutor _abrir() => driftDatabase(name: 'gestor_encargos');

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (_) async {
      // SQLite trae las llaves foráneas **apagadas** por defecto. Hoy ninguna
      // tabla declara FK (ver `tablas.dart`); queda encendido para que la
      // primera que lo haga no las tenga decorativas.
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

  /// Vacía **todas** las tablas (datos del negocio, Outbox y metadatos). Para
  /// cuando estos datos dejan de ser de quien usa el teléfono: cierre de sesión
  /// o entrada con otra cuenta.
  ///
  /// Recorre [allTables], así que una tabla nueva queda cubierta sin tocar
  /// esto. Las llaves foráneas se difieren al final de la transacción: el
  /// orden de borrado entre padres e hijos deja de importar.
  Future<void> borrarTodo() => transaction(() async {
    await customStatement('PRAGMA defer_foreign_keys = ON');
    for (final tabla in allTables) {
      await delete(tabla).go();
    }
  });
}
