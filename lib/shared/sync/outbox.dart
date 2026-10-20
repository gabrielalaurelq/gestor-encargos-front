import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../infrastructure/db/base_datos.dart';
import '../infrastructure/http/error_api.dart';
import 'colecciones.dart';

export '../infrastructure/db/base_datos.dart' show OperacionOutbox;

/// Tipos de operación que el motor necesita reconocer. Las features agregan
/// los suyos; acá solo los que tienen tratamiento especial al subir.
abstract final class TiposOperacion {
  /// Lleva el número Hi/Lo: si se encoló sin número, se le asigna al subir.
  static const crearEncargo = 'crear_encargo';
}

/// Lo que una feature encola al escribir en local (Doc 7, Bloque 3: el
/// repositorio escribe primero en Drift y deja la operación para el push).
class OperacionNueva {
  const OperacionNueva({
    required this.tipo,
    required this.metodo,
    required this.ruta,
    required this.entidadId,
    this.cuerpo,
    this.encargoId,
  });

  final String tipo;

  /// `POST`, `PATCH` o `DELETE`.
  final String metodo;
  final String ruta;
  final Json? cuerpo;
  final String entidadId;
  final String? encargoId;
}

/// Una operación que el servidor rechazó, para la lista de "no
/// sincronizadas": qué se intentó, sobre qué encargo, y qué dijo el servidor.
class OperacionApartada {
  const OperacionApartada({
    required this.id,
    required this.tipo,
    required this.entidadId,
    required this.encargoId,
    required this.codigo,
    required this.mensaje,
  });

  final int id;
  final String tipo;
  final String entidadId;

  /// El encargo a marcar en la UI (decisión del usuario).
  final String? encargoId;

  /// Código del catálogo del Doc 5 (`DESCUENTO_INVALIDO`, `NO_ENCONTRADO`…).
  final String codigo;
  final String mensaje;
}

extension OperacionOutboxJson on OperacionOutbox {
  Json? get cuerpoJson => cuerpo == null ? null : jsonDecode(cuerpo!) as Json;
}

/// La cola de escrituras pendientes de subir.
class Outbox {
  Outbox(this._base, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final BaseDatos _base;
  final DateTime Function() _reloj;
  final _encoladas = StreamController<void>.broadcast();

  /// Un aviso por cada operación encolada: el motor la sube en cuanto puede.
  Stream<void> get encoladas => _encoladas.stream;

  /// Llamarla **dentro de la misma transacción** que la escritura local: o
  /// quedan las dos o ninguna. Un cambio local sin su operación nunca subiría;
  /// una operación sin su cambio local subiría algo que el usuario no ve.
  Future<int> encolar(OperacionNueva operacion) async {
    final id = await _base
        .into(_base.operacionesOutbox)
        .insert(
          OperacionesOutboxCompanion.insert(
            tipo: operacion.tipo,
            metodo: operacion.metodo,
            ruta: operacion.ruta,
            cuerpo: Value(operacion.cuerpo == null ? null : jsonEncode(operacion.cuerpo)),
            entidadId: operacion.entidadId,
            encargoId: Value(operacion.encargoId),
            creadoEn: _reloj().toUtc().toIso8601String(),
          ),
        );
    _encoladas.add(null);
    return id;
  }

  /// La más antigua de las pendientes; las apartadas no bloquean la cola.
  Future<OperacionOutbox?> siguiente() {
    final consulta = _base.select(_base.operacionesOutbox)
      ..where((o) => o.apartadaCodigo.isNull())
      ..orderBy([(o) => OrderingTerm.asc(o.id)])
      ..limit(1);
    return consulta.getSingleOrNull();
  }

  Future<void> completar(int id) =>
      (_base.delete(_base.operacionesOutbox)..where((o) => o.id.equals(id))).go();

  Future<void> registrarFallo(int id, ErrorApi error) => _base.customUpdate(
    'UPDATE outbox_operations SET intentos = intentos + 1, ultimo_error = ? WHERE id = ?',
    variables: [Variable.withString(error.codigo), Variable.withInt(id)],
    updates: {_base.operacionesOutbox},
  );

  Future<void> apartar(int id, ErrorApi error) =>
      (_base.update(_base.operacionesOutbox)..where((o) => o.id.equals(id))).write(
        OperacionesOutboxCompanion(
          apartadaCodigo: Value(error.codigo),
          apartadaMensaje: Value(error.mensaje),
        ),
      );

  /// Filas que el pull no debe pisar: las de toda operación de la cola,
  /// **pendiente o apartada**. Una apartada conserva la versión local —la que
  /// el servidor rechazó— para que el usuario vea qué no se guardó, en vez de
  /// que el siguiente pull la reemplace en silencio.
  Future<Set<String>> idsProtegidos() async {
    final tabla = _base.operacionesOutbox;
    final consulta = _base.selectOnly(tabla)..addColumns([tabla.entidadId, tabla.encargoId]);
    final filas = await consulta.get();
    return {
      for (final fila in filas) ...[fila.read(tabla.entidadId)!, ?fila.read(tabla.encargoId)],
    };
  }

  /// Cuántas esperan subir. Las apartadas no cuentan: ya no van a subir.
  Stream<int> pendientes() {
    final cantidad = _base.operacionesOutbox.id.count();
    final consulta = _base.selectOnly(_base.operacionesOutbox)
      ..addColumns([cantidad])
      ..where(_base.operacionesOutbox.apartadaCodigo.isNull());
    return consulta.map((fila) => fila.read(cantidad)!).watchSingle();
  }

  /// La lista de "no sincronizadas".
  Stream<List<OperacionApartada>> apartadas() {
    final consulta = _base.select(_base.operacionesOutbox)
      ..where((o) => o.apartadaCodigo.isNotNull())
      ..orderBy([(o) => OrderingTerm.asc(o.id)]);
    return consulta
        .map(
          (o) => OperacionApartada(
            id: o.id,
            tipo: o.tipo,
            entidadId: o.entidadId,
            encargoId: o.encargoId,
            codigo: o.apartadaCodigo!,
            mensaje: o.apartadaMensaje ?? '',
          ),
        )
        .watch();
  }

  Future<void> cerrar() => _encoladas.close();
}
