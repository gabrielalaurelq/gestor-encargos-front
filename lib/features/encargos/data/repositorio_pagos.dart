import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/domain/dia.dart';
import '../../../shared/domain/monto.dart';
import '../../../shared/domain/origen_pago.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/infrastructure/db/base_datos.dart';
import '../../../shared/sync/outbox.dart';
import '../../../shared/sync/recalculo.dart';
import '../domain/estado_encargo.dart';
import '../domain/pago.dart';
import 'estado_local.dart';

abstract final class TiposPago {
  static const registrar = 'registrar_pago';
  static const eliminar = 'eliminar_pago';
}

/// Los pagos de un encargo (S3c). Cada escritura, en una transacción: el
/// pago en Drift, el recálculo local del saldo ([recalcularTotales]) y la
/// operación en el Outbox.
///
/// Un encargo cancelado no recibe ni pierde pagos; uno entregado sí, porque
/// se puede entregar fiado y cobrar después (decisión del usuario, Doc 7
/// v1.3).
class RepositorioPagos {
  RepositorioPagos({
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

  /// En el orden en que se hicieron, con el nombre de su origen.
  Stream<List<Pago>> observar(String encargoId) {
    final pagos = _base.pagos;
    final origenes = _base.origenesPago;
    final consulta =
        _base.select(pagos).join([leftOuterJoin(origenes, origenes.id.equalsExp(pagos.origenId))])
          ..where(pagos.encargoId.equals(encargoId))
          ..orderBy([
            OrderingTerm.asc(pagos.fecha),
            OrderingTerm.asc(pagos.creadoEn),
            OrderingTerm.asc(pagos.id),
          ]);
    return consulta.map((fila) {
      final pago = fila.readTable(pagos);
      return Pago(
        id: pago.id,
        encargoId: pago.encargoId,
        monto: Monto.desdeCentimos(pago.monto),
        origenId: pago.origenId,
        origenNombre: fila.readTableOrNull(origenes)?.nombre,
        tipoCodigo: pago.tipo,
        fecha: diaDesdeIso(pago.fecha),
      );
    }).watch();
  }

  /// Los que se ofrecen al registrar (invariante 5). Vacía si el catálogo
  /// nunca se bajó.
  Stream<List<OrigenPago>> observarOrigenesActivos() {
    final consulta = _base.select(_base.origenesPago)
      ..where((o) => o.activo.equals(true))
      ..orderBy([(o) => OrderingTerm.asc(o.id)]);
    return consulta
        .map((fila) => OrigenPago(id: fila.id, nombre: fila.nombre, activo: fila.activo))
        .watch();
  }

  /// La fecha es la del teléfono y no se elige (Doc 2, invariante 4).
  Future<Pago> registrar(
    String encargoId, {
    required Monto monto,
    required int origenId,
    required TipoPago tipo,
  }) async {
    final valido = ReglasPago.validarMonto(monto);
    final id = _nuevoId();
    final ahora = _reloj();
    final fecha = isoDesdeDia(hoyDelNegocio(ahora));
    return _base.transaction(() async {
      await _comprobarNoCancelado(encargoId);
      final origen = await (_base.select(
        _base.origenesPago,
      )..where((o) => o.id.equals(origenId))).getSingleOrNull();
      if (origen == null || !origen.activo) {
        throw const ValorInvalido(
          'ORIGEN_PAGO_INVALIDO',
          'Ese medio de pago ya no está disponible.',
        );
      }
      await _base
          .into(_base.pagos)
          .insert(
            PagosCompanion.insert(
              id: id,
              creadoEn: ahora.toUtc().toIso8601String(),
              actualizadoEn: sinVersionDelServidor,
              encargoId: encargoId,
              monto: valido.centimos,
              origenId: origenId,
              tipo: tipo.codigo,
              fecha: fecha,
            ),
          );
      await recalcularTotales(_base, encargoId);
      await _outbox.encolar(
        OperacionNueva(
          tipo: TiposPago.registrar,
          metodo: 'POST',
          ruta: '/encargos/$encargoId/pagos',
          cuerpo: {
            'id': id,
            'monto': valido.soles,
            'origen_id': origenId,
            'tipo': tipo.codigo,
            'fecha': fecha,
          },
          entidadId: id,
          encargoId: encargoId,
        ),
      );
      return Pago(
        id: id,
        encargoId: encargoId,
        monto: valido,
        origenId: origenId,
        origenNombre: origen.nombre,
        tipoCodigo: tipo.codigo,
        fecha: diaDesdeIso(fecha),
      );
    });
  }

  /// El saldo vuelve a subir (PRD módulo 5).
  Future<void> eliminar(Pago pago) => _base.transaction(() async {
    await _comprobarNoCancelado(pago.encargoId);
    await (_base.delete(_base.pagos)..where((p) => p.id.equals(pago.id))).go();
    await recalcularTotales(_base, pago.encargoId);
    await _outbox.encolar(
      OperacionNueva(
        tipo: TiposPago.eliminar,
        metodo: 'DELETE',
        ruta: '/encargos/${pago.encargoId}/pagos/${pago.id}',
        entidadId: pago.id,
        encargoId: pago.encargoId,
      ),
    );
  });

  Future<void> _comprobarNoCancelado(String encargoId) async {
    if (await leerEstadoLocal(_base, encargoId) == EstadoEncargo.cancelado) {
      throw const ValorInvalido('ENCARGO_CERRADO', 'Un encargo cancelado no cambia sus pagos.');
    }
  }
}
