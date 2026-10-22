import '../../../shared/domain/monto.dart';
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

  /// El descuento como lo teclea el usuario: vacío es S/ 0 (sin descuento).
  static Monto leerDescuento(String texto) =>
      texto.trim().isEmpty ? Monto.cero : validarDescuento(Monto.desde(texto), null);

  /// Doc 2, invariante 2 (`DESCUENTO_INVALIDO`, con los mensajes del backend):
  /// ni negativo ni mayor que la suma de trabajos. Sin [sumaTrabajos] solo
  /// mira el signo.
  static Monto validarDescuento(Monto descuento, Monto? sumaTrabajos) {
    if (descuento.esNegativo) {
      throw const ValorInvalido('DESCUENTO_INVALIDO', 'El descuento no puede ser negativo.');
    }
    if (sumaTrabajos != null && descuento > sumaTrabajos) {
      throw const ValorInvalido(
        'DESCUENTO_INVALIDO',
        'El descuento no puede ser mayor a la suma de los trabajos.',
      );
    }
    return descuento;
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
