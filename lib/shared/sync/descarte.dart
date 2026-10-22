import 'package:drift/drift.dart';

import '../infrastructure/db/base_datos.dart';
import '../infrastructure/http/cliente_api.dart';
import '../infrastructure/http/error_api.dart';
import 'colecciones.dart';
import 'outbox.dart';
import 'recalculo.dart';

/// De qué recurso del servidor se recupera la versión actual al descartar.
enum Recurso { cliente, servicio, encargo }

/// Lo que la pantalla de "Cambios no guardados" dice de una operación y
/// cómo se deshace. Cada módulo nuevo agrega aquí sus tipos (una línea).
class TipoDeOperacion {
  const TipoDeOperacion(this.accion, this.recurso, {this.alta = false});

  /// "Editar encargo", en lenguaje del negociante.
  final String accion;
  final Recurso recurso;

  /// Crea la fila: si se descarta, lo que dependa de ella también cae.
  final bool alta;
}

/// Los mismos códigos que encolan las features (`TiposCliente`,
/// `TiposServicio`, `TiposEncargo`, `TiposTrabajo`, `TiposPago`);
/// `descarte_test.dart` comprueba que coincidan.
const tiposDeOperacion = <String, TipoDeOperacion>{
  'crear_cliente': TipoDeOperacion('Agregar cliente', Recurso.cliente, alta: true),
  'editar_cliente': TipoDeOperacion('Editar cliente', Recurso.cliente),
  'crear_servicio': TipoDeOperacion('Agregar servicio', Recurso.servicio, alta: true),
  'editar_servicio': TipoDeOperacion('Cambiar servicio', Recurso.servicio),
  'crear_encargo': TipoDeOperacion('Crear encargo', Recurso.encargo, alta: true),
  'editar_encargo': TipoDeOperacion('Editar encargo', Recurso.encargo),
  'crear_trabajo': TipoDeOperacion('Agregar trabajo', Recurso.encargo, alta: true),
  'editar_trabajo': TipoDeOperacion('Editar trabajo', Recurso.encargo),
  'eliminar_trabajo': TipoDeOperacion('Eliminar trabajo', Recurso.encargo),
  'registrar_pago': TipoDeOperacion('Registrar pago', Recurso.encargo, alta: true),
  'eliminar_pago': TipoDeOperacion('Eliminar pago', Recurso.encargo),
};

/// "Descartar" una operación apartada (Doc 7 v1.2, decisión del usuario):
/// se borra la operación y las posteriores sobre la misma fila, y la fila
/// vuelve a la versión que tiene el servidor.
///
/// **Primero se pide la versión, después se toca la base**, todo en una
/// transacción: sin conexión ([SinConexion]) no cambia nada. Pedirla hace
/// falta porque la bajada delta solo trae lo cambiado después de su marca;
/// sin esto la fila quedaría para siempre con la versión rechazada.
class Descarte {
  Descarte({required this._base, required this._api});

  final BaseDatos _base;
  final ClienteApi _api;

  Future<void> descartar(OperacionApartada operacion) async {
    final tipo = tiposDeOperacion[operacion.tipo];
    final recurso = tipo?.recurso ?? (operacion.encargoId != null ? Recurso.encargo : null);
    final aplicar = switch (recurso) {
      Recurso.cliente => await _cliente(operacion.entidadId),
      Recurso.servicio => await _servicio(operacion.entidadId),
      Recurso.encargo => await _encargo(operacion.encargoId ?? operacion.entidadId),
      // Un tipo desconocido sin encargo: solo se quita de la cola.
      null => (Set<String> _) async {},
    };
    await _base.transaction(() async {
      await _quitar(operacion, alta: tipo?.alta ?? false);
      await aplicar(await _conOperaciones());
    });
  }

  /// La rechazada y las posteriores sobre la misma fila; si era un alta,
  /// también las de sus hijos (fallarían igual: el padre no existe).
  Future<void> _quitar(OperacionApartada operacion, {required bool alta}) {
    final tabla = _base.operacionesOutbox;
    return (_base.delete(tabla)..where((o) {
          final mismaFila = o.entidadId.equals(operacion.entidadId);
          final suyas = alta ? mismaFila | o.encargoId.equals(operacion.entidadId) : mismaFila;
          return o.id.isBiggerOrEqualValue(operacion.id) & suyas;
        }))
        .go();
  }

  /// Filas con otras operaciones en la cola: esas siguen ganando (Doc 7
  /// v1.1, "lo local pendiente gana") y no se pisan.
  Future<Set<String>> _conOperaciones() async {
    final tabla = _base.operacionesOutbox;
    final filas = await (_base.selectOnly(tabla)..addColumns([tabla.entidadId])).get();
    return {for (final fila in filas) fila.read(tabla.entidadId)!};
  }

  /// `null` si el servidor no lo tiene (`404`: un alta que nunca existió).
  Future<Json?> _pedir(String ruta, {Map<String, Object?>? query}) async {
    try {
      return await _api.get(ruta, query: query) as Json;
    } on ErrorRechazado catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
  }

  Future<_Aplicar> _cliente(String id) async {
    final json = await _pedir('/clientes/$id');
    return (Set<String> protegidas) async {
      if (protegidas.contains(id)) return;
      await _reemplazar('clientes', id, json);
    };
  }

  /// No hay `GET /servicios/{id}`: se recorre el catálogo completo (es corto).
  Future<_Aplicar> _servicio(String id) async {
    Json? encontrado;
    for (var pagina = 1; encontrado == null; pagina++) {
      final respuesta = (await _pedir(
        '/servicios',
        query: {'incluir_inactivos': true, 'pagina': pagina, 'por_pagina': 100},
      ))!;
      final datos = (respuesta['datos']! as List).cast<Json>();
      encontrado = datos.where((s) => s['id'] == id).firstOrNull;
      if (datos.length < 100) break;
    }
    final json = encontrado;
    return (Set<String> protegidas) async {
      if (protegidas.contains(id)) return;
      await _reemplazar('servicios', id, json);
    };
  }

  /// `GET /encargos/{id}` trae el agregado entero: el encargo y sus hijos se
  /// dejan como en el servidor, salvo filas con otras operaciones en cola.
  /// Al final se recalculan el total y el saldo en local: si quedó algún hijo
  /// propio sin subir, los del servidor todavía no lo cuentan.
  Future<_Aplicar> _encargo(String id) async {
    final json = await _pedir('/encargos/$id');
    return (Set<String> protegidas) async {
      // Hijos por colección local, con el `encargo_id` que el detalle omite.
      final hijos = <String, List<Json>>{
        'objetos_recibidos': [for (final o in _lista(json, 'objetos')) _con(o, id)],
        'trabajos': [for (final t in _lista(json, 'trabajos')) _con(t, id)],
        'materiales': [
          for (final t in _lista(json, 'trabajos'))
            for (final m in _lista(t, 'materiales')) m,
        ],
        'pagos': [for (final p in _lista(json, 'pagos')) _con(p, id)],
        'notas': [for (final n in _lista(json, 'notas')) _con(n, id)],
        'fotos': [for (final f in _lista(json, 'fotos')) _con(f, id)],
      };
      if (!protegidas.contains(id)) await _reemplazar('encargos', id, json);

      final trabajosLocales = await (_base.select(
        _base.trabajos,
      )..where((t) => t.encargoId.equals(id))).map((t) => t.id).get();
      final locales = <String, List<String>>{
        'objetos_recibidos': await _ids(_base.objetosRecibidos, 'encargo_id', [id]),
        'trabajos': trabajosLocales,
        'materiales': await _ids(_base.materiales, 'trabajo_id', trabajosLocales),
        'pagos': await _ids(_base.pagos, 'encargo_id', [id]),
        'notas': await _ids(_base.notas, 'encargo_id', [id]),
        'fotos': await _ids(_base.fotos, 'encargo_id', [id]),
      };
      for (final MapEntry(key: clave, value: filas) in hijos.entries) {
        final delServidor = {for (final f in filas) f['id']! as String};
        for (final fila in filas) {
          final filaId = fila['id']! as String;
          if (!protegidas.contains(filaId)) await _reemplazar(clave, filaId, fila);
        }
        for (final local in locales[clave]!) {
          if (!delServidor.contains(local) && !protegidas.contains(local)) {
            await _reemplazar(clave, local, null);
          }
        }
      }
      await recalcularTotales(_base, id);
    };
  }

  static List<Json> _lista(Json? json, String clave) =>
      ((json?[clave] as List?) ?? const []).cast<Json>();

  static Json _con(Json hijo, String encargoId) => {...hijo, 'encargo_id': encargoId};

  Future<List<String>> _ids(
    TableInfo<Table, Object?> tabla,
    String columna,
    List<String> padres,
  ) async {
    if (padres.isEmpty) return const [];
    final marcadores = List.filled(padres.length, '?').join(', ');
    final filas = await _base
        .customSelect(
          'SELECT id FROM "${tabla.actualTableName}" WHERE "$columna" IN ($marcadores)',
          variables: [for (final p in padres) Variable.withString(p)],
          readsFrom: {tabla},
        )
        .get();
    return [for (final f in filas) f.read<String>('id')];
  }

  /// La versión del servidor tal cual (sin la guarda de `actualizado_en` de
  /// la bajada: es la verdad actual), o borrar si no la tiene.
  Future<void> _reemplazar(String clave, String id, Json? json) async {
    final coleccion = colecciones.firstWhere((c) => c.clave == clave);
    final tabla = coleccion.tabla(_base);
    if (json == null) {
      await _base.customUpdate(
        'DELETE FROM "${tabla.actualTableName}" WHERE "id" = ?',
        variables: [Variable.withString(id)],
        updates: {tabla},
        updateKind: UpdateKind.delete,
      );
    } else {
      await _base.into(tabla).insertOnConflictUpdate(coleccion.aFila(json));
    }
  }
}

typedef _Aplicar = Future<void> Function(Set<String> protegidas);
