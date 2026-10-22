import '../../../shared/domain/monto.dart';
import '../../../shared/domain/valor_invalido.dart';

/// Un Trabajo del encargo (PRD módulo 4): desde el catálogo —descripción y
/// precio copiados, con el precio bloqueado (Doc 2, invariante 13)— o
/// personalizado, con los dos libres.
class Trabajo {
  const Trabajo({
    required this.id,
    required this.encargoId,
    required this.servicioId,
    this.objetoRecibidoId,
    required this.descripcion,
    required this.precio,
  });

  final String id;
  final String encargoId;

  /// Solo rastro de procedencia: el precio ya quedó copiado.
  final String? servicioId;

  /// El objeto recibido al que corresponde, si se vinculó (Caso 6).
  final String? objetoRecibidoId;
  final String descripcion;
  final Monto precio;

  /// Vino del catálogo: el precio no se edita (sí la descripción).
  bool get delCatalogo => servicioId != null;
}

/// Las reglas del backend (`trabajo.ts`), con sus códigos: se validan antes
/// de guardar para que un rechazo del servidor nunca sea culpa del usuario.
abstract final class ReglasTrabajo {
  static String validarDescripcion(String descripcion) {
    final limpia = descripcion.trim();
    if (limpia.isEmpty) {
      throw const ValorInvalido('TRABAJO_DESCRIPCION_VACIA', 'Escribe qué trabajo es.');
    }
    return limpia;
  }

  /// El precio tal como lo teclea el usuario. El cero vale (PRD módulo 4:
  /// retoque de garantía); negativo no.
  static Monto leerPrecio(String texto) {
    if (texto.trim().isEmpty) {
      throw const ValorInvalido('TRABAJO_PRECIO_INVALIDO', 'Escribe el precio.');
    }
    return validarPrecio(Monto.desde(texto));
  }

  static Monto validarPrecio(Monto precio) {
    if (precio.esNegativo) {
      throw const ValorInvalido('TRABAJO_PRECIO_INVALIDO', 'El precio no puede ser negativo.');
    }
    return precio;
  }
}
