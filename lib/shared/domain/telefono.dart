import 'valor_invalido.dart';

/// E.164: el mismo patrón que el backend (`+`, código de país sin 0
/// inicial, 7 a 15 dígitos en total).
final _e164 = RegExp(r'^\+[1-9]\d{6,14}$');

/// Celular peruano: 9 dígitos que empiezan en 9.
final _celularPeru = RegExp(r'^9\d{8}$');

const _prefijoPeru = '+51';

/// Value Object Teléfono (Doc 2).
///
/// **La normalización vive acá, no en el backend.** El backend exige E.164 ya
/// formado y no adivina el país (Doc 5, `TELEFONO_INVALIDO`); el PRD (módulo 1)
/// pone esa decisión en la UI: teclado peruano de 9 dígitos por defecto, y un
/// interruptor explícito para números de otro país. Por eso hay dos
/// constructores y no uno que "intente adivinar".
class Telefono {
  const Telefono._(this.valor);

  /// Siempre en E.164 (`+51987654321`): es lo que viaja a la API.
  final String valor;

  /// Lo que teclea el usuario en el modo por defecto. Se toleran espacios y
  /// guiones, que la gente pone al dictar un número.
  factory Telefono.peruano(String nueveDigitos) {
    final limpio = nueveDigitos.replaceAll(RegExp(r'[\s-]'), '');
    if (!_celularPeru.hasMatch(limpio)) {
      throw const ValorInvalido(
        'TELEFONO_INVALIDO',
        'El celular debe tener 9 dígitos y empezar con 9.',
      );
    }
    return Telefono._('$_prefijoPeru$limpio');
  }

  /// Modo internacional: el número completo, con `+` y código de país. Es
  /// también como llega desde la API.
  factory Telefono.e164(String valor) {
    final limpio = valor.replaceAll(RegExp(r'[\s-]'), '');
    if (!_e164.hasMatch(limpio)) {
      throw const ValorInvalido(
        'TELEFONO_INVALIDO',
        'Escriba el número completo con + y código de país (ej. +34 612 345 678).',
      );
    }
    return Telefono._(limpio);
  }

  bool get esPeruano => valor.startsWith(_prefijoPeru) && valor.length == 12;

  /// Sin el `+`, como lo pide el enlace de WhatsApp (Doc 10).
  String get digitos => valor.substring(1);

  /// "987 654 321" para un celular peruano; el E.164 tal cual para el resto.
  String formatear() {
    if (!esPeruano) return valor;
    final n = valor.substring(3);
    return '${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6)}';
  }

  @override
  bool operator ==(Object other) => other is Telefono && other.valor == valor;

  @override
  int get hashCode => valor.hashCode;

  @override
  String toString() => valor;
}
