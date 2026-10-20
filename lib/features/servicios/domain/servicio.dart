import '../../../shared/domain/monto.dart';
import '../../../shared/domain/valor_invalido.dart';

/// Un ítem del Catálogo de servicios (Doc 2, agregado Servicio): nombre +
/// precio fijo que se copia, congelado, a cada Trabajo creado desde él.
///
/// Las reglas son las del backend (`servicio.ts`), con sus mismos códigos: se
/// validan acá antes de guardar para que un rechazo del servidor —que el
/// Outbox apartaría— sea solo culpa de un error nuestro, nunca del usuario.
class Servicio {
  const Servicio({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.activo,
  });

  final String id;

  /// No se edita (Doc 5: el `PATCH` solo cambia precio y `activo`): para
  /// corregirlo se desactiva el servicio y se crea otro.
  final String nombre;
  final Monto precio;

  /// Un servicio desactivado deja de ofrecerse para trabajos nuevos, pero no
  /// se borra nunca (Doc 2, invariante 14) y se puede reactivar.
  final bool activo;

  static String validarNombre(String nombre) {
    final limpio = nombre.trim();
    if (limpio.isEmpty) {
      throw const ValorInvalido('SERVICIO_NOMBRE_VACIO', 'Escribe el nombre del servicio.');
    }
    return limpio;
  }

  /// El precio tal como lo teclea el usuario. El cero vale (PRD módulo 4: un
  /// retoque de garantía); negativo no (Doc 4, `CHECK precio >= 0`).
  static Monto leerPrecio(String texto) {
    if (texto.trim().isEmpty) {
      throw const ValorInvalido('SERVICIO_PRECIO_INVALIDO', 'Escribe el precio.');
    }
    return validarPrecio(Monto.desde(texto));
  }

  static Monto validarPrecio(Monto precio) {
    if (precio.esNegativo) {
      throw const ValorInvalido(
        'SERVICIO_PRECIO_INVALIDO',
        'El precio de un servicio no puede ser negativo.',
      );
    }
    return precio;
  }
}
