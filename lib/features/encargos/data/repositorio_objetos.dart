import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/infrastructure/db/base_datos.dart';
import '../../../shared/sync/outbox.dart';
import '../domain/objeto_recibido.dart';
import 'estado_local.dart';

abstract final class TiposObjeto {
  static const crear = 'crear_objeto';
  static const editar = 'editar_objeto';
  static const eliminar = 'eliminar_objeto';
}

/// Los objetos recibidos de un encargo (S3d1). Cada escritura, en una
/// transacción con su operación en el Outbox. Un objeto no tiene precio: no
/// hay recálculo.
///
/// Un encargo entregado o cancelado no cambia sus objetos (decisión del
/// usuario, la misma regla que Trabajos).
class RepositorioObjetos {
  RepositorioObjetos({
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

  /// En el orden en que se agregaron.
  Stream<List<ObjetoRecibido>> observar(String encargoId) {
    final consulta = _base.select(_base.objetosRecibidos)
      ..where((o) => o.encargoId.equals(encargoId))
      ..orderBy([(o) => OrderingTerm.asc(o.creadoEn), (o) => OrderingTerm.asc(o.id)]);
    return consulta
        .map(
          (fila) =>
              ObjetoRecibido(id: fila.id, encargoId: fila.encargoId, descripcion: fila.descripcion),
        )
        .watch();
  }

  Future<ObjetoRecibido> agregar(String encargoId, {required String descripcion}) async {
    final limpia = ReglasObjeto.validarDescripcion(descripcion);
    final objeto = ObjetoRecibido(id: _nuevoId(), encargoId: encargoId, descripcion: limpia);
    return _base.transaction(() async {
      await _comprobarAbierto(encargoId);
      await _base
          .into(_base.objetosRecibidos)
          .insert(
            ObjetosRecibidosCompanion.insert(
              id: objeto.id,
              creadoEn: _reloj().toUtc().toIso8601String(),
              actualizadoEn: sinVersionDelServidor,
              encargoId: encargoId,
              descripcion: limpia,
            ),
          );
      await _outbox.encolar(
        OperacionNueva(
          tipo: TiposObjeto.crear,
          metodo: 'POST',
          ruta: '/encargos/$encargoId/objetos',
          cuerpo: {'id': objeto.id, 'descripcion': limpia},
          entidadId: objeto.id,
          encargoId: encargoId,
        ),
      );
      return objeto;
    });
  }

  /// Sin cambios no encola nada y devuelve `false`.
  Future<bool> editar(ObjetoRecibido actual, {required String descripcion}) async {
    final limpia = ReglasObjeto.validarDescripcion(descripcion);
    if (limpia == actual.descripcion) return false;
    return _base.transaction(() async {
      await _comprobarAbierto(actual.encargoId);
      final filas =
          await (_base.update(_base.objetosRecibidos)..where((o) => o.id.equals(actual.id))).write(
            ObjetosRecibidosCompanion(descripcion: Value(limpia)),
          );
      if (filas == 0) throw StateError('No existe el objeto ${actual.id}');
      await _outbox.encolar(
        OperacionNueva(
          tipo: TiposObjeto.editar,
          metodo: 'PATCH',
          ruta: '/encargos/${actual.encargoId}/objetos/${actual.id}',
          cuerpo: {'descripcion': limpia},
          entidadId: actual.id,
          encargoId: actual.encargoId,
        ),
      );
      return true;
    });
  }

  /// Como la cascada del backend (Doc 5 v1.5): sus fotos se borran y sus
  /// trabajos **se quedan**, sin objeto. Los pagos no se tocan (Doc 2,
  /// invariante 15).
  Future<void> eliminar(ObjetoRecibido objeto) => _base.transaction(() async {
    await _comprobarAbierto(objeto.encargoId);
    await (_base.delete(_base.fotos)..where((f) => f.objetoRecibidoId.equals(objeto.id))).go();
    await (_base.update(_base.trabajos)..where((t) => t.objetoRecibidoId.equals(objeto.id))).write(
      const TrabajosCompanion(objetoRecibidoId: Value(null)),
    );
    await (_base.delete(_base.objetosRecibidos)..where((o) => o.id.equals(objeto.id))).go();
    await _outbox.encolar(
      OperacionNueva(
        tipo: TiposObjeto.eliminar,
        metodo: 'DELETE',
        ruta: '/encargos/${objeto.encargoId}/objetos/${objeto.id}',
        entidadId: objeto.id,
        encargoId: objeto.encargoId,
      ),
    );
  });

  Future<void> _comprobarAbierto(String encargoId) async {
    if ((await leerEstadoLocal(_base, encargoId))?.cerrado ?? false) {
      throw const ValorInvalido(
        'ENCARGO_CERRADO',
        'Un encargo entregado o cancelado no cambia sus objetos.',
      );
    }
  }
}
