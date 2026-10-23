import 'package:drift/drift.dart';

import '../../../shared/domain/dia.dart';
import '../../../shared/domain/monto.dart';
import '../../../shared/infrastructure/db/base_datos.dart';
import '../../encargos/domain/estado_encargo.dart';
import '../../encargos/domain/fila_encargo.dart';
import '../domain/dashboard.dart';

/// Las consultas del Dashboard (S5a), todas sobre Drift: no hay endpoint
/// propio, los datos ya están en el teléfono. Se filtra y suma en SQL, no en
/// Dart, para que miles de encargos no pesen (índice local
/// `encargos_entrega`).
class RepositorioDashboard {
  RepositorioDashboard({required this._base});

  final BaseDatos _base;

  static final _activos = [
    for (final estado in EstadoEncargo.values)
      if (!estado.cerrado) estado.codigo,
  ];

  Stream<ResumenDashboard> observarResumen() {
    final marcas = List.filled(_activos.length, '?').join(', ');
    return _base
        .customSelect(
          'SELECT '
          '(SELECT COUNT(*) FROM encargos WHERE estado IN ($marcas)) AS activos, '
          '(SELECT COALESCE(SUM(saldo_pendiente), 0) FROM encargos '
          "WHERE estado <> 'CANCELADO' AND saldo_pendiente > 0) AS saldo",
          variables: [for (final codigo in _activos) Variable.withString(codigo)],
          readsFrom: {_base.encargos},
        )
        .watchSingle()
        .map(
          (fila) => ResumenDashboard(
            activos: fila.read<int>('activos'),
            saldoPendiente: Monto.desdeCentimos(fila.read<int>('saldo')),
          ),
        );
  }

  /// [hoy] es el día del negocio. Atrasados: regla de [estaAtrasado], la
  /// misma del Detalle. Entregas de hoy: acordada hoy y sin cerrar.
  Stream<PendientesDelDia> observarPendientes(DateTime hoy) {
    final dia = isoDesdeDia(hoy);
    final e = _base.encargos;
    final consulta =
        _base.select(e).join([
            leftOuterJoin(_base.clientes, _base.clientes.id.equalsExp(e.clienteId)),
          ])
          ..where(
            (e.estado.equals(EstadoEncargo.cancelado.codigo).not() &
                    e.fechaListo.isNull() &
                    e.fechaEntregaAcordada.isSmallerThanValue(dia)) |
                (e.fechaEntregaAcordada.equals(dia) &
                    e.estado.isNotIn([
                      EstadoEncargo.entregado.codigo,
                      EstadoEncargo.cancelado.codigo,
                    ])),
          )
          ..orderBy([
            OrderingTerm.asc(e.fechaEntregaAcordada),
            OrderingTerm.asc(e.creadoEn),
            OrderingTerm.asc(e.id),
          ]);
    return consulta.watch().map((filas) {
      final atrasados = <FilaEncargo>[];
      final deHoy = <FilaEncargo>[];
      for (final fila in filas) {
        final encargo = _aFila(fila.readTable(e), fila.readTableOrNull(_base.clientes));
        (encargo.atrasadoEl(hoy) ? atrasados : deHoy).add(encargo);
      }
      return PendientesDelDia(atrasados: atrasados, entregasHoy: deHoy);
    });
  }

  static FilaEncargo _aFila(EncargoFila fila, ClienteFila? cliente) {
    DateTime? diaOpcional(String? iso) => iso == null ? null : diaDesdeIso(iso);
    return FilaEncargo(
      id: fila.id,
      numero: fila.numero,
      clienteNombre: cliente?.nombre,
      descripcion: fila.descripcion,
      codigoEstado: fila.estado,
      fechaEntregaAcordada: diaDesdeIso(fila.fechaEntregaAcordada),
      fechaListo: diaOpcional(fila.fechaListo),
      fechaEntregaReal: diaOpcional(fila.fechaEntregaReal),
      saldoPendiente: Monto.desdeCentimos(fila.saldoPendiente),
      creadoEn: fila.creadoEn,
    );
  }
}
