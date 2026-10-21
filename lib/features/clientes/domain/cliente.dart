import '../../../shared/domain/telefono.dart';
import '../../../shared/domain/valor_invalido.dart';

/// Quien encarga trabajos (Doc 2, agregado Cliente; PRD módulo 1).
class Cliente {
  const Cliente({required this.id, required this.nombre, this.telefono});

  final String id;
  final String nombre;

  /// Opcional (PRD: un cliente ocasional puede no dejarlo; solo pierde el
  /// enlace de WhatsApp). No es único: el backend admite repetidos.
  final Telefono? telefono;

  static String validarNombre(String nombre) {
    final limpio = nombre.trim();
    if (limpio.isEmpty) {
      throw const ValorInvalido('CLIENTE_NOMBRE_VACIO', 'Escribe el nombre del cliente.');
    }
    return limpio;
  }

  /// El teléfono tal como lo teclea el usuario, según el modo de la hoja:
  /// 9 dígitos peruanos por defecto, o el número completo con `+` si activó
  /// "Número de otro país" (PRD módulo 1). Vacío = sin teléfono.
  static Telefono? leerTelefono(String texto, {required bool internacional}) {
    if (texto.trim().isEmpty) return null;
    return internacional ? Telefono.e164(texto) : Telefono.peruano(texto);
  }
}
