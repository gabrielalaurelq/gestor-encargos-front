import '../../../shared/domain/valor_invalido.dart';

/// Reglas del alta mínima de un encargo (PRD módulo 2, Caso 7): cliente,
/// descripción y fecha de entrega acordada; nada más es obligatorio.
abstract final class ReglasEncargo {
  static String validarDescripcion(String descripcion) {
    final limpia = descripcion.trim();
    if (limpia.isEmpty) {
      throw const ValorInvalido('ENCARGO_DESCRIPCION_VACIA', 'Escribe qué hay que hacer.');
    }
    return limpia;
  }
}

/// Lo que devuelve el alta: lo justo para abrir su detalle y avisar.
class EncargoNuevo {
  const EncargoNuevo({required this.id, required this.numero});

  final String id;

  /// `null` si el bloque de números se agotó sin conexión: se numera al subir
  /// (Doc 7 v1.1).
  final int? numero;
}
