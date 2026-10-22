import 'package:drift/drift.dart';

import '../../../shared/infrastructure/db/base_datos.dart';
import '../../../shared/sync/descarte.dart';
import '../../../shared/sync/outbox.dart';

/// Una operación que el servidor rechazó, contada como la entiende el
/// negociante: "Editar encargo · #47 · Ana García".
class CambioNoGuardado {
  const CambioNoGuardado({required this.operacion, required this.accion, required this.sobre});

  final OperacionApartada operacion;

  /// "Editar encargo".
  final String accion;

  /// "#47 · Ana García", "Ana García", "Basta"… o genérico si la fila ya no
  /// está en el teléfono.
  final String sobre;

  /// Para "Ver encargo"; `null` si no es de un encargo.
  String? get encargoId => operacion.encargoId;

  /// El motivo del servidor, que ya viene en español (Doc 5, Bloque 3).
  String get motivo =>
      operacion.mensaje.trim().isEmpty ? 'El servidor no lo aceptó.' : operacion.mensaje;
}

/// La lista de "Cambios no guardados" (Doc 7 v1.2), reactiva: se vacía sola
/// al descartar.
class CambiosNoGuardados {
  CambiosNoGuardados({required this._base, required this._outbox});

  final BaseDatos _base;
  final Outbox _outbox;

  Stream<List<CambioNoGuardado>> observar() => _outbox.apartadas().asyncMap(
    (apartadas) async => [for (final op in apartadas) await _describir(op)],
  );

  Future<CambioNoGuardado> _describir(OperacionApartada op) async {
    final tipo = tiposDeOperacion[op.tipo];
    final recurso = tipo?.recurso ?? (op.encargoId != null ? Recurso.encargo : null);
    final sobre = switch (recurso) {
      Recurso.cliente => await _nombreCliente(op.entidadId) ?? 'un cliente',
      Recurso.servicio => await _nombreServicio(op.entidadId) ?? 'un servicio',
      Recurso.encargo => await _encargo(op.encargoId ?? op.entidadId) ?? 'un encargo',
      null => 'un dato',
    };
    return CambioNoGuardado(operacion: op, accion: tipo?.accion ?? 'Cambio', sobre: sobre);
  }

  Future<String?> _nombreCliente(String id) => (_base.select(
    _base.clientes,
  )..where((c) => c.id.equals(id))).map((c) => c.nombre).getSingleOrNull();

  Future<String?> _nombreServicio(String id) => (_base.select(
    _base.servicios,
  )..where((s) => s.id.equals(id))).map((s) => s.nombre).getSingleOrNull();

  Future<String?> _encargo(String id) async {
    final fila = await (_base.select(_base.encargos).join([
      leftOuterJoin(_base.clientes, _base.clientes.id.equalsExp(_base.encargos.clienteId)),
    ])..where(_base.encargos.id.equals(id))).getSingleOrNull();
    if (fila == null) return null;
    final numero = fila.readTable(_base.encargos).numero;
    return [
      numero == null ? 'sin número' : '#$numero',
      ?fila.readTableOrNull(_base.clientes)?.nombre,
    ].join(' · ');
  }
}
