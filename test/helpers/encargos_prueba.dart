import 'package:drift/drift.dart';
import 'package:gestor_encargos/shared/infrastructure/db/base_datos.dart';

/// Encargos y pagos escritos directo en Drift, como si hubieran bajado del
/// servidor: hasta el Sprint 2 la app no los crea.
Future<void> insertarEncargo(
  BaseDatos base, {
  required String id,
  required String clienteId,
  required String creadoEn,
  int? numero,
  String descripcion = 'Basta de pantalón',
  String estado = 'INGRESADO',
  int saldoCentimos = 0,
  String entregaAcordada = '2026-10-23',
  String? entregaReal,
}) => base
    .into(base.encargos)
    .insert(
      EncargosCompanion.insert(
        id: id,
        creadoEn: creadoEn,
        actualizadoEn: creadoEn,
        clienteId: clienteId,
        numero: Value(numero),
        descripcion: descripcion,
        estado: estado,
        precioTotal: saldoCentimos,
        descuento: 0,
        saldoPendiente: saldoCentimos,
        fechaEntregaPrometida: entregaAcordada,
        fechaEntregaAcordada: entregaAcordada,
        fechaEntregaReal: Value(entregaReal),
      ),
    );

Future<void> insertarPago(
  BaseDatos base, {
  required String id,
  required String encargoId,
  required int centimos,
}) => base
    .into(base.pagos)
    .insert(
      PagosCompanion.insert(
        id: id,
        creadoEn: '2026-10-20T15:00:00.000Z',
        actualizadoEn: '2026-10-20T15:00:00.000Z',
        encargoId: encargoId,
        monto: centimos,
        origenId: 1,
        tipo: 'ADELANTO',
        fecha: '2026-10-20',
      ),
    );
