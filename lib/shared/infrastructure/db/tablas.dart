import 'package:drift/drift.dart';

// Tablas espejo de las 9 colecciones de `GET /sync` (Doc 5, Bloque 1), con
// las columnas del Doc 4. Las llena el motor de sync; las features las leen.
//
// Convenciones, iguales en todas:
// - **Dinero en céntimos enteros** (`Monto`): un `REAL` sumaría distinto que
//   el servidor y los saldos "saltarían" al sincronizar.
// - **Fechas de hecho** (`DATE` del Doc 4) como texto `AAAA-MM-DD`: no tienen
//   hora ni zona, y así no hay conversión que las corra un día.
// - **Marcas del servidor** (`creado_en`, `actualizado_en`) como el texto ISO
//   tal cual llega (`toISOString`, ancho fijo y en UTC): se comparan como
//   texto en el Last-Write-Wins sin perder los milisegundos.
// - **Sin llaves foráneas declaradas**, a propósito. `/sync` pagina cada
//   colección por separado (`has_more`): la página 1 puede traer un trabajo
//   cuyo encargo llega en la página 2. Una FK rechazaría ese hijo y la
//   sincronización no avanzaría nunca. La integridad la garantiza el servidor;
//   la base local es su copia, y al terminar de paginar queda completa.
// - **Sin `eliminado_en`**: un tombstone borra la fila local (la UI nunca
//   muestra lo borrado).

/// `actualizado_en` de una fila creada en el teléfono, que el servidor todavía
/// no devolvió: menor que cualquier marca real.
///
/// **Las escrituras locales no adelantan `actualizado_en`.** Esa columna es
/// "la versión del servidor que tengo", y el pull solo acepta una igual o más
/// nueva. Si guardara la hora del teléfono y el reloj fuera adelantado, la
/// versión del servidor quedaría rechazada para siempre. Lo que hace ganar a
/// un cambio local mientras no sube es el Outbox (`idsProtegidos`), no esta
/// marca: una edición conserva la que tenía y una alta lleva esta.
const sinVersionDelServidor = '0000-01-01T00:00:00.000Z';

mixin _Sincronizada on Table {
  TextColumn get id => text()();
  TextColumn get creadoEn => text()();
  TextColumn get actualizadoEn => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ClienteFila')
@TableIndex(name: 'clientes_nombre_busqueda', columns: {#nombreBusqueda})
class Clientes extends Table with _Sincronizada {
  TextColumn get nombre => text()();

  /// `normalizarBusqueda(nombre)`: SQLite no ignora tildes, así que la forma
  /// con la que se busca y ordena se guarda calculada. Solo existe en local.
  TextColumn get nombreBusqueda => text()();

  /// E.164 (`Telefono`), opcional.
  TextColumn get telefono => text().nullable()();
}

@DataClassName('ServicioFila')
class Servicios extends Table with _Sincronizada {
  TextColumn get nombre => text()();
  IntColumn get precio => integer()();
  BoolColumn get activo => boolean()();
}

@DataClassName('EncargoFila')
@TableIndex(name: 'encargos_cliente', columns: {#clienteId})
class Encargos extends Table with _Sincronizada {
  TextColumn get clienteId => text()();

  /// Asignado con los bloques Hi/Lo (Doc 3, ADR-008); `null` mientras no hay.
  IntColumn get numero => integer().nullable()();
  TextColumn get descripcion => text()();
  TextColumn get estado => text()();
  IntColumn get precioTotal => integer()();
  IntColumn get descuento => integer()();
  IntColumn get saldoPendiente => integer()();
  TextColumn get ubicacionFisica => text().nullable()();
  TextColumn get notasGenerales => text().nullable()();
  TextColumn get fechaEntregaPrometida => text()();
  TextColumn get fechaEntregaAcordada => text()();
  TextColumn get fechaListo => text().nullable()();
  TextColumn get fechaEntregaReal => text().nullable()();
}

@DataClassName('ObjetoRecibidoFila')
@TableIndex(name: 'objetos_recibidos_encargo', columns: {#encargoId})
class ObjetosRecibidos extends Table with _Sincronizada {
  TextColumn get encargoId => text()();
  TextColumn get descripcion => text()();
}

@DataClassName('TrabajoFila')
@TableIndex(name: 'trabajos_encargo', columns: {#encargoId})
class Trabajos extends Table with _Sincronizada {
  TextColumn get encargoId => text()();
  TextColumn get servicioId => text().nullable()();
  TextColumn get objetoRecibidoId => text().nullable()();
  TextColumn get descripcion => text()();
  IntColumn get precio => integer()();
}

@DataClassName('MaterialFila')
@TableIndex(name: 'materiales_trabajo', columns: {#trabajoId})
class Materiales extends Table with _Sincronizada {
  TextColumn get trabajoId => text()();
  TextColumn get nombre => text()();

  /// Texto libre ("2 metros", "1 rollo"), como en el Doc 4.
  TextColumn get cantidad => text().nullable()();
  IntColumn get costo => integer().nullable()();
}

@DataClassName('PagoFila')
@TableIndex(name: 'pagos_encargo', columns: {#encargoId})
@TableIndex(name: 'pagos_fecha', columns: {#fecha})
class Pagos extends Table with _Sincronizada {
  TextColumn get encargoId => text()();
  IntColumn get monto => integer()();
  IntColumn get origenId => integer()();
  TextColumn get tipo => text()();
  TextColumn get fecha => text()();
}

@DataClassName('NotaFila')
@TableIndex(name: 'notas_encargo', columns: {#encargoId})
class Notas extends Table with _Sincronizada {
  TextColumn get encargoId => text()();
  TextColumn get texto => text()();
  TextColumn get fecha => text()();
}

@DataClassName('FotoFila')
@TableIndex(name: 'fotos_encargo', columns: {#encargoId})
class Fotos extends Table with _Sincronizada {
  TextColumn get encargoId => text()();
  TextColumn get objetoRecibidoId => text().nullable()();

  /// URL firmada de R2, válida 7 días (Doc 5 v1.5). Bajar el archivo y
  /// guardarlo en el teléfono es trabajo de la pantalla de fotos.
  TextColumn get urlDescarga => text().nullable()();
  TextColumn get urlDescargaExpiraEn => text().nullable()();
}

// --- Propia del dispositivo -------------------------------------------------

/// Cola Outbox (Doc 3; Doc 7, Bloque 3: `outbox_operations`): cada escritura
/// hecha en el teléfono, a la espera de subir al servidor como una llamada
/// REST normal, en el orden en que se hizo.
///
/// Una operación está **pendiente** o **apartada** (`apartadaCodigo` con
/// valor): el servidor la rechazó con un error permanente y reintentarla no
/// cambiaría nada (decisión del usuario, Sprint 0: se aparta y la cola sigue).
@DataClassName('OperacionOutbox')
class OperacionesOutbox extends Table {
  @override
  String get tableName => 'outbox_operations';

  /// `AUTOINCREMENT`: los ids nunca se reutilizan ni retroceden, así que
  /// ordenar por id es ordenar por momento de encolado.
  IntColumn get id => integer().autoIncrement()();

  /// Qué hizo el usuario (`crear_encargo`, `registrar_pago`…): para los
  /// mensajes de la lista de no sincronizadas y para preparar el envío.
  TextColumn get tipo => text()();
  TextColumn get metodo => text()();
  TextColumn get ruta => text()();

  /// JSON del cuerpo, tal cual se enviará.
  TextColumn get cuerpo => text().nullable()();

  /// Fila espejo que esta operación modifica: el pull no la pisa mientras la
  /// operación exista.
  TextColumn get entidadId => text()();

  /// Raíz del agregado (Doc 2): el servidor recalcula sus totales al recibir
  /// la operación, así que también se protege.
  TextColumn get encargoId => text().nullable()();

  IntColumn get intentos => integer().withDefault(const Constant(0))();

  /// Reloj del dispositivo, ISO. Solo informativo: el orden lo da el id.
  TextColumn get creadoEn => text()();

  /// Código del último error transitorio, para diagnóstico.
  TextColumn get ultimoError => text().nullable()();

  TextColumn get apartadaCodigo => text().nullable()();
  TextColumn get apartadaMensaje => text().nullable()();
}

/// Catálogo `origenes_pago` del sistema (Efectivo, Transferencia, Yape,
/// Plin), bajado de `GET /origenes-pago` (Doc 5 v1.6, Doc 7 v1.3). No es una
/// colección de `/sync`: no pertenece a ningún negocio, así que no tiene
/// marcas de versión y se reemplaza entero. Guarda también los desactivados:
/// un pago viejo sigue nombrando su origen.
@DataClassName('OrigenPagoFila')
class OrigenesPago extends Table {
  @override
  String get tableName => 'origenes_pago';

  IntColumn get id => integer()();
  TextColumn get nombre => text()();
  BoolColumn get activo => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
