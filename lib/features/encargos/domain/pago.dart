import '../../../shared/domain/monto.dart';
import '../../../shared/domain/valor_invalido.dart';
import 'estado_encargo.dart';

/// Los dos tipos del PRD (módulo 5), con los códigos del backend.
enum TipoPago {
  adelanto('ADELANTO', 'Adelanto'),
  pago('PAGO', 'Pago');

  const TipoPago(this.codigo, this.etiqueta);

  final String codigo;
  final String etiqueta;

  static TipoPago? desde(String codigo) {
    for (final tipo in values) {
      if (tipo.codigo == codigo) return tipo;
    }
    return null;
  }

  /// El que se propone al registrar (decisión del usuario, Doc 7 v1.3):
  /// "Adelanto" mientras el trabajo no está listo, "Pago" desde LISTO. El
  /// negociante siempre puede cambiarlo.
  static TipoPago propuestoPara(EstadoEncargo? estado) =>
      estado == EstadoEncargo.listo || estado == EstadoEncargo.entregado ? pago : adelanto;
}

/// Un pago del encargo (PRD módulo 5). No se edita: si hubo un error se
/// elimina y se registra de nuevo (Doc 5, sin `PATCH`).
class Pago {
  const Pago({
    required this.id,
    required this.encargoId,
    required this.monto,
    required this.origenId,
    required this.origenNombre,
    required this.tipoCodigo,
    required this.fecha,
  });

  final String id;
  final String encargoId;
  final Monto monto;
  final int origenId;

  /// `null` si el catálogo todavía no se bajó al teléfono.
  final String? origenNombre;

  /// Tal como viene, por si el backend agrega un tipo que esta app no conoce.
  final String tipoCodigo;

  /// La fecha del teléfono al registrarlo (Doc 2, invariante 4).
  final DateTime fecha;

  TipoPago? get tipo => TipoPago.desde(tipoCodigo);
}

/// Las reglas del backend (`pago.ts`), con sus códigos.
abstract final class ReglasPago {
  static Monto leerMonto(String texto) {
    if (texto.trim().isEmpty) {
      throw const ValorInvalido('PAGO_MONTO_INVALIDO', 'Escribe el monto.');
    }
    return validarMonto(Monto.desde(texto));
  }

  /// Mayor que cero (Doc 4, `CHECK monto > 0`). Que supere el saldo **sí**
  /// vale: queda a favor del cliente (PRD módulo 5).
  static Monto validarMonto(Monto monto) {
    if (!(monto > Monto.cero)) {
      throw const ValorInvalido('PAGO_MONTO_INVALIDO', 'El monto debe ser mayor a S/ 0.');
    }
    return monto;
  }
}
