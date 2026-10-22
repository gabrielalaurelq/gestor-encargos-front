import '../../../shared/domain/valor_invalido.dart';

/// Lo que el cliente deja en el negocio, o el material que aporta (PRD
/// módulo 3). Solo texto libre: sin categorías ni checklist.
class ObjetoRecibido {
  const ObjetoRecibido({required this.id, required this.encargoId, required this.descripcion});

  final String id;
  final String encargoId;
  final String descripcion;
}

/// Las reglas del backend (`objeto-recibido.ts`), con su código.
abstract final class ReglasObjeto {
  static String validarDescripcion(String descripcion) {
    final limpia = descripcion.trim();
    if (limpia.isEmpty) {
      throw const ValorInvalido('OBJETO_DESCRIPCION_VACIA', 'Escribe qué dejó el cliente.');
    }
    return limpia;
  }
}
