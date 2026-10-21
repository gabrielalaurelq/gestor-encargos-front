import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/domain/telefono.dart';
import '../../../shared/domain/texto_busqueda.dart';
import '../../../shared/infrastructure/db/base_datos.dart';
import '../../../shared/sync/outbox.dart';
import '../domain/cliente.dart';

abstract final class TiposCliente {
  static const crear = 'crear_cliente';
  static const editar = 'editar_cliente';
}

/// `%` y `_` son comodines de `LIKE`: escritos por el usuario se buscan tal
/// cual, igual que en el backend (`GET /buscar`).
String _escaparLike(String texto) => texto.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');

/// Los clientes en la base local. Mismo patrón que el catálogo: cada escritura
/// va a Drift y encola su envío en la misma transacción, sin adelantar
/// `actualizado_en` (ver `sinVersionDelServidor`).
class RepositorioClientes {
  RepositorioClientes({
    required this._base,
    required this._outbox,
    String Function()? nuevoId,
    DateTime Function()? reloj,
  }) : _nuevoId = nuevoId ?? const Uuid().v4,
       _reloj = reloj ?? DateTime.now;

  final BaseDatos _base;
  final Outbox _outbox;
  final String Function() _nuevoId;
  final DateTime Function() _reloj;

  /// Búsqueda en tiempo real (PRD módulo 1, Caso 8): parte del nombre, sin
  /// importar mayúsculas ni tildes, o dígitos del teléfono ("987 65" encuentra
  /// `+51987654321`). Texto vacío = todos. Por nombre, alfabético.
  Stream<List<Cliente>> buscar(String texto) {
    final nombre = normalizarBusqueda(texto);
    final digitos = texto.replaceAll(RegExp(r'\D'), '');
    final consulta = _base.select(_base.clientes)
      ..orderBy([(c) => OrderingTerm.asc(c.nombreBusqueda), (c) => OrderingTerm.asc(c.id)]);
    if (nombre.isNotEmpty) {
      consulta.where((c) {
        final porNombre = c.nombreBusqueda.like('%${_escaparLike(nombre)}%', escapeChar: r'\');
        return digitos.isEmpty ? porNombre : porNombre | c.telefono.like('%$digitos%');
      });
    }
    return consulta.map(_aCliente).watch();
  }

  /// Uno solo, reactivo; `null` si no existe (o lo borró otro dispositivo).
  Stream<Cliente?> observar(String id) => (_base.select(
    _base.clientes,
  )..where((c) => c.id.equals(id))).map(_aCliente).watchSingleOrNull();

  /// Para el aviso de teléfono repetido (decisión del usuario): no bloquea,
  /// solo avisa. [excepto] es el propio cliente, al editar.
  Future<List<Cliente>> conTelefono(Telefono telefono, {String? excepto}) {
    final consulta = _base.select(_base.clientes)
      ..where((c) {
        final mismo = c.telefono.equals(telefono.valor);
        return excepto == null ? mismo : mismo & c.id.equals(excepto).not();
      })
      ..orderBy([(c) => OrderingTerm.asc(c.nombreBusqueda)]);
    return consulta.map(_aCliente).get();
  }

  Future<Cliente> crear({required String nombre, Telefono? telefono}) async {
    final cliente = Cliente(
      id: _nuevoId(),
      nombre: Cliente.validarNombre(nombre),
      telefono: telefono,
    );
    return _base.transaction(() async {
      await _base
          .into(_base.clientes)
          .insert(
            ClientesCompanion.insert(
              id: cliente.id,
              creadoEn: _reloj().toUtc().toIso8601String(),
              actualizadoEn: sinVersionDelServidor,
              nombre: cliente.nombre,
              nombreBusqueda: normalizarBusqueda(cliente.nombre),
              telefono: Value(telefono?.valor),
            ),
          );
      await _outbox.encolar(
        OperacionNueva(
          tipo: TiposCliente.crear,
          metodo: 'POST',
          ruta: '/clientes',
          cuerpo: {'id': cliente.id, 'nombre': cliente.nombre, 'telefono': telefono?.valor},
          entidadId: cliente.id,
        ),
      );
      return cliente;
    });
  }

  /// `PATCH` solo con lo que cambió; sin cambios, no encola nada. Un teléfono
  /// que pasa a `null` viaja como `null`: el backend lo borra (ausente sería
  /// "no tocar").
  Future<Cliente> editar(Cliente actual, {required String nombre, Telefono? telefono}) async {
    final limpio = Cliente.validarNombre(nombre);
    final cuerpo = <String, Object?>{
      if (limpio != actual.nombre) 'nombre': limpio,
      if (telefono != actual.telefono) 'telefono': telefono?.valor,
    };
    final editado = Cliente(id: actual.id, nombre: limpio, telefono: telefono);
    if (cuerpo.isEmpty) return editado;
    return _base.transaction(() async {
      final filas = await (_base.update(_base.clientes)..where((c) => c.id.equals(actual.id)))
          .write(
            ClientesCompanion(
              nombre: Value(limpio),
              nombreBusqueda: Value(normalizarBusqueda(limpio)),
              telefono: Value(telefono?.valor),
            ),
          );
      if (filas == 0) throw StateError('No existe el cliente ${actual.id}');
      await _outbox.encolar(
        OperacionNueva(
          tipo: TiposCliente.editar,
          metodo: 'PATCH',
          ruta: '/clientes/${actual.id}',
          cuerpo: cuerpo,
          entidadId: actual.id,
        ),
      );
      return editado;
    });
  }

  static Cliente _aCliente(ClienteFila fila) => Cliente(
    id: fila.id,
    nombre: fila.nombre,
    telefono: fila.telefono == null ? null : Telefono.e164(fila.telefono!),
  );
}
