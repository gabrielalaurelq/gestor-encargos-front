import 'package:drift/drift.dart';

import '../domain/monto.dart';
import '../infrastructure/db/base_datos.dart';

typedef Json = Map<String, Object?>;

/// Una colección de `GET /sync`: la clave con que llega, su tabla espejo y
/// cómo se convierte una fila del JSON (Doc 5) en una fila de Drift.
class Coleccion {
  const Coleccion(this.clave, this.tabla, this.aFila);

  final String clave;
  final TableInfo<Table, Object?> Function(BaseDatos base) tabla;
  final Insertable<Object?> Function(Json json) aFila;
}

/// Las 9 colecciones, padres antes que hijos. Las tablas no tienen llaves
/// foráneas (ver `tablas.dart`), así que el orden no es obligatorio; se
/// conserva para que, dentro de una página, una consulta nunca vea un hijo
/// cuyo padre venía en la misma página y aún no se aplicó.
final colecciones = <Coleccion>[
  Coleccion('clientes', (b) => b.clientes, _cliente),
  Coleccion('servicios', (b) => b.servicios, _servicio),
  Coleccion('encargos', (b) => b.encargos, _encargo),
  Coleccion('objetos_recibidos', (b) => b.objetosRecibidos, _objeto),
  Coleccion('trabajos', (b) => b.trabajos, _trabajo),
  Coleccion('materiales', (b) => b.materiales, _material),
  Coleccion('pagos', (b) => b.pagos, _pago),
  Coleccion('notas', (b) => b.notas, _nota),
  Coleccion('fotos', (b) => b.fotos, _foto),
];

String _texto(Json j, String clave) => j[clave]! as String;
String? _textoONulo(Json j, String clave) => j[clave] as String?;

/// El dinero llega como número con 2 decimales (Doc 5); se guarda en céntimos.
int _centimos(Json j, String clave) => Monto.desde(j[clave]!).centimos;
int? _centimosONulo(Json j, String clave) =>
    j[clave] == null ? null : Monto.desde(j[clave]!).centimos;

ClientesCompanion _cliente(Json j) => ClientesCompanion.insert(
  id: _texto(j, 'id'),
  creadoEn: _texto(j, 'creado_en'),
  actualizadoEn: _texto(j, 'actualizado_en'),
  nombre: _texto(j, 'nombre'),
  telefono: Value(_textoONulo(j, 'telefono')),
);

ServiciosCompanion _servicio(Json j) => ServiciosCompanion.insert(
  id: _texto(j, 'id'),
  creadoEn: _texto(j, 'creado_en'),
  actualizadoEn: _texto(j, 'actualizado_en'),
  nombre: _texto(j, 'nombre'),
  precio: _centimos(j, 'precio'),
  activo: j['activo']! as bool,
);

EncargosCompanion _encargo(Json j) => EncargosCompanion.insert(
  id: _texto(j, 'id'),
  creadoEn: _texto(j, 'creado_en'),
  actualizadoEn: _texto(j, 'actualizado_en'),
  clienteId: _texto(j, 'cliente_id'),
  numero: Value(j['numero'] as int?),
  descripcion: _texto(j, 'descripcion'),
  estado: _texto(j, 'estado'),
  precioTotal: _centimos(j, 'precio_total'),
  descuento: _centimos(j, 'descuento'),
  saldoPendiente: _centimos(j, 'saldo_pendiente'),
  ubicacionFisica: Value(_textoONulo(j, 'ubicacion_fisica')),
  notasGenerales: Value(_textoONulo(j, 'notas_generales')),
  fechaEntregaPrometida: _texto(j, 'fecha_entrega_prometida'),
  fechaEntregaAcordada: _texto(j, 'fecha_entrega_acordada'),
  fechaListo: Value(_textoONulo(j, 'fecha_listo')),
  fechaEntregaReal: Value(_textoONulo(j, 'fecha_entrega_real')),
);

ObjetosRecibidosCompanion _objeto(Json j) => ObjetosRecibidosCompanion.insert(
  id: _texto(j, 'id'),
  creadoEn: _texto(j, 'creado_en'),
  actualizadoEn: _texto(j, 'actualizado_en'),
  encargoId: _texto(j, 'encargo_id'),
  descripcion: _texto(j, 'descripcion'),
);

TrabajosCompanion _trabajo(Json j) => TrabajosCompanion.insert(
  id: _texto(j, 'id'),
  creadoEn: _texto(j, 'creado_en'),
  actualizadoEn: _texto(j, 'actualizado_en'),
  encargoId: _texto(j, 'encargo_id'),
  servicioId: Value(_textoONulo(j, 'servicio_id')),
  objetoRecibidoId: Value(_textoONulo(j, 'objeto_recibido_id')),
  descripcion: _texto(j, 'descripcion'),
  precio: _centimos(j, 'precio'),
);

MaterialesCompanion _material(Json j) => MaterialesCompanion.insert(
  id: _texto(j, 'id'),
  creadoEn: _texto(j, 'creado_en'),
  actualizadoEn: _texto(j, 'actualizado_en'),
  trabajoId: _texto(j, 'trabajo_id'),
  nombre: _texto(j, 'nombre'),
  cantidad: Value(_textoONulo(j, 'cantidad')),
  costo: Value(_centimosONulo(j, 'costo')),
);

PagosCompanion _pago(Json j) => PagosCompanion.insert(
  id: _texto(j, 'id'),
  creadoEn: _texto(j, 'creado_en'),
  actualizadoEn: _texto(j, 'actualizado_en'),
  encargoId: _texto(j, 'encargo_id'),
  monto: _centimos(j, 'monto'),
  origenId: j['origen_id']! as int,
  tipo: _texto(j, 'tipo'),
  fecha: _texto(j, 'fecha'),
);

NotasCompanion _nota(Json j) => NotasCompanion.insert(
  id: _texto(j, 'id'),
  creadoEn: _texto(j, 'creado_en'),
  actualizadoEn: _texto(j, 'actualizado_en'),
  encargoId: _texto(j, 'encargo_id'),
  texto: _texto(j, 'texto'),
  fecha: _texto(j, 'fecha'),
);

FotosCompanion _foto(Json j) => FotosCompanion.insert(
  id: _texto(j, 'id'),
  creadoEn: _texto(j, 'creado_en'),
  actualizadoEn: _texto(j, 'actualizado_en'),
  encargoId: _texto(j, 'encargo_id'),
  objetoRecibidoId: Value(_textoONulo(j, 'objeto_recibido_id')),
  urlDescarga: Value(_textoONulo(j, 'url_descarga')),
  urlDescargaExpiraEn: Value(_textoONulo(j, 'url_descarga_expira_en')),
);
