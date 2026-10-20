import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../infrastructure/db/base_datos.dart';
import '../infrastructure/http/cliente_api.dart';
import '../infrastructure/http/error_api.dart';
import '../infrastructure/providers.dart';
import 'colecciones.dart';

part 'bajada.g.dart';

/// Ids de filas con operaciones pendientes en la Outbox. El pull **no las
/// toca** (decisión del usuario, Sprint 0): lo local pendiente gana hasta que
/// sube, y el Last-Write-Wins real lo decide el servidor al recibir el push.
/// Hasta que exista la Outbox (F3b) no hay ninguna.
typedef IdsProtegidos = Future<Set<String>> Function();

Future<Set<String>> _ninguno() async => const {};

class ResultadoBajada {
  const ResultadoBajada({required this.paginas, required this.resincronizo});

  final int paginas;

  /// El servidor respondió `410` y se rehízo la base desde cero.
  final bool resincronizo;
}

/// Mitad "pull" del motor de sincronización (Doc 5, Bloque 1; Doc 7, Bloque
/// 3): trae de `GET /sync` lo cambiado desde la última vez y lo aplica a las
/// tablas espejo.
///
/// Reglas, todas del Doc 5:
/// - **El próximo `since` es el `servidor_timestamp`** de la respuesta, nunca
///   el máximo `actualizado_en` visto. Se guarda **en la misma transacción**
///   que los cambios de esa página: si la app muere a mitad, o se aplicó la
///   página entera y avanzó la marca, o nada.
/// - **Las filas llegan repetidas** (margen de solape de 10 s, `since`
///   inclusivo): aplicar es idempotente — upsert por id.
/// - **Una fila más vieja nunca pisa una más nueva**: el upsert solo escribe
///   si `actualizado_en` no retrocede.
/// - **Un tombstone** (`eliminado_en`) borra la fila local.
/// - **`has_more`** → se pide la página siguiente con la marca recibida.
/// - **`410`** → se descartan los datos ya sincronizados (nunca las filas con
///   cambios pendientes) y se repite sin `since`.
class Bajada {
  Bajada({required this._api, required this._base, IdsProtegidos? idsProtegidos})
    : _idsProtegidos = idsProtegidos ?? _ninguno;

  final ClienteApi _api;
  final BaseDatos _base;
  final IdsProtegidos _idsProtegidos;

  static const claveSince = 'sync.since';

  Future<ResultadoBajada>? _enCurso;

  /// Si ya hay una bajada en curso, devuelve esa: dos a la vez aplicarían las
  /// mismas páginas y competirían por la marca `since`.
  ///
  /// Los errores de la API ([ErrorApi]) suben tal cual; quien programa las
  /// sincronizaciones decide si reintentar. Lo ya aplicado queda aplicado.
  Future<ResultadoBajada> bajar() => _enCurso ??= _bajar().whenComplete(() => _enCurso = null);

  Future<ResultadoBajada> _bajar() async {
    var paginas = 0;
    var resincronizo = false;
    while (true) {
      final since = await _base.leerMetadato(claveSince);
      final Json respuesta;
      try {
        respuesta = await _api.get('/sync', query: {'since': since}) as Json;
      } on SyncDemasiadoAntiguo {
        // Sin `since` el servidor nunca responde 410; un segundo 410 sería un
        // error del servidor, y reintentar giraría para siempre.
        if (resincronizo) rethrow;
        await _descartarSincronizado();
        resincronizo = true;
        continue;
      }

      final siguiente = respuesta['servidor_timestamp']! as String;
      final hayMas = respuesta['has_more'] == true;
      await _aplicar(respuesta['cambios']! as Map, siguiente);
      paginas++;
      if (!hayMas) return ResultadoBajada(paginas: paginas, resincronizo: resincronizo);
      if (siguiente == since) {
        // La marca no avanzó: pedir otra vez daría la misma página. Es el
        // límite conocido del backend (500 filas con el mismo
        // `actualizado_en`); mejor fallar a la vista que girar en vacío.
        throw StateError('GET /sync devolvió has_more sin avanzar la marca ($since)');
      }
    }
  }

  Future<void> _aplicar(Map<Object?, Object?> cambios, String siguiente) {
    return _base.transaction(() async {
      final protegidos = await _idsProtegidos();
      for (final coleccion in colecciones) {
        final tabla = coleccion.tabla(_base);
        final filas = (cambios[coleccion.clave] as List?) ?? const [];
        for (final fila in filas.cast<Json>()) {
          final id = fila['id']! as String;
          if (protegidos.contains(id)) continue;
          if (fila['eliminado_en'] != null) {
            await _borrar(tabla, id);
          } else {
            await _guardar(tabla, coleccion.aFila(fila));
          }
        }
      }
      await _base.guardarMetadato(claveSince, siguiente);
    });
  }

  Future<void> _guardar(TableInfo<Table, Object?> tabla, Insertable<Object?> fila) {
    return _base
        .into(tabla)
        .insert(
          fila,
          onConflict: DoUpdate(
            (_) => fila,
            // `excluded` es la fila que se intentó insertar. Las marcas son
            // texto ISO de ancho fijo en UTC: compararlas como texto es
            // compararlas en el tiempo.
            where: (_) => CustomExpression<bool>(
              '"${tabla.actualTableName}"."actualizado_en" <= "excluded"."actualizado_en"',
            ),
          ),
        );
  }

  Future<void> _borrar(TableInfo<Table, Object?> tabla, String id) {
    // `customUpdate` y no `customStatement`: avisa a los streams de Drift que
    // la tabla cambió, y la UI se refresca sola.
    return _base.customUpdate(
      'DELETE FROM "${tabla.actualTableName}" WHERE "id" = ?',
      variables: [Variable.withString(id)],
      updates: {tabla},
      updateKind: UpdateKind.delete,
    );
  }

  /// Respuesta a un `410`: todo lo que vino del servidor se borra y se vuelve
  /// a pedir. Lo que tiene cambios pendientes se queda — son escrituras
  /// propias que el servidor todavía no conoce. Borrado y marca van juntos:
  /// si la app muere en medio, la próxima bajada arranca de cero igual.
  Future<void> _descartarSincronizado() {
    return _base.transaction(() async {
      final protegidos = (await _idsProtegidos()).toList();
      final marcadores = List.filled(protegidos.length, '?').join(', ');
      for (final coleccion in colecciones) {
        final tabla = coleccion.tabla(_base);
        await _base.customUpdate(
          protegidos.isEmpty
              ? 'DELETE FROM "${tabla.actualTableName}"'
              : 'DELETE FROM "${tabla.actualTableName}" WHERE "id" NOT IN ($marcadores)',
          variables: [for (final id in protegidos) Variable.withString(id)],
          updates: {tabla},
          updateKind: UpdateKind.delete,
        );
      }
      await _base.borrarMetadato(claveSince);
    });
  }
}

@Riverpod(keepAlive: true)
Bajada bajada(Ref ref) =>
    Bajada(api: ref.watch(clienteApiProvider), base: ref.watch(baseDatosProvider));
