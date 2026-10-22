import 'package:drift/drift.dart';

import '../domain/monto.dart';
import '../domain/totales_encargo.dart';
import '../infrastructure/db/base_datos.dart';

/// Recalcula en local el total, el descuento y el saldo de un encargo a partir
/// de sus trabajos y pagos en Drift ([TotalesEncargo]). Va dentro de la misma
/// transacción que la escritura del hijo, y no adelanta `actualizado_en` (ver
/// `sinVersionDelServidor`): la versión del servidor llega después por
/// `/sync`. Sin el encargo en el teléfono no hace nada.
Future<void> recalcularTotales(BaseDatos base, String encargoId) async {
  final encargo = await (base.select(
    base.encargos,
  )..where((e) => e.id.equals(encargoId))).getSingleOrNull();
  if (encargo == null) return;

  Future<Monto> sumar(ResultSetImplementation<HasResultSet, dynamic> tabla, String columna) async {
    final fila = await base
        .customSelect(
          'SELECT COALESCE(SUM("$columna"), 0) AS suma FROM "${tabla.entityName}" '
          'WHERE "encargo_id" = ?',
          variables: [Variable.withString(encargoId)],
          readsFrom: {tabla},
        )
        .getSingle();
    return Monto.desdeCentimos(fila.read<int>('suma'));
  }

  final totales = TotalesEncargo.calcular(
    sumaTrabajos: await sumar(base.trabajos, 'precio'),
    descuento: Monto.desdeCentimos(encargo.descuento),
    sumaPagos: await sumar(base.pagos, 'monto'),
  );
  await (base.update(base.encargos)..where((e) => e.id.equals(encargoId))).write(
    EncargosCompanion(
      precioTotal: Value(totales.precioTotal.centimos),
      descuento: Value(totales.descuento.centimos),
      saldoPendiente: Value(totales.saldoPendiente.centimos),
    ),
  );
}
