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
  String? entregaPrometida,
  String? listo,
  String? entregaReal,
  int? precioCentimos,
  int descuentoCentimos = 0,
  String? ubicacion,
  String? notas,
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
        precioTotal: precioCentimos ?? saldoCentimos,
        descuento: descuentoCentimos,
        saldoPendiente: saldoCentimos,
        fechaEntregaPrometida: entregaPrometida ?? entregaAcordada,
        fechaEntregaAcordada: entregaAcordada,
        fechaListo: Value(listo),
        fechaEntregaReal: Value(entregaReal),
        ubicacionFisica: Value(ubicacion),
        notasGenerales: Value(notas),
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

/// El catálogo de la semilla del backend (Doc 4), como si ya se hubiera
/// bajado de `GET /origenes-pago`. Los nombres en [inactivos] van
/// desactivados.
Future<void> insertarOrigenes(BaseDatos base, {Set<String> inactivos = const {}}) => base.batch(
  (lote) => lote.insertAll(base.origenesPago, [
    for (final (i, nombre) in ['Efectivo', 'Transferencia', 'Yape', 'Plin'].indexed)
      OrigenesPagoCompanion.insert(
        id: Value(i + 1),
        nombre: nombre,
        activo: !inactivos.contains(nombre),
      ),
  ]),
);
