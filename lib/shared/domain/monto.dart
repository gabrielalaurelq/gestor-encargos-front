import 'valor_invalido.dart';

/// Doc 4: el dinero es DECIMAL(10,2) — hasta 8 dígitos enteros y 2
/// decimales. Mismo patrón que el `Monto` del backend, a propósito: lo que
/// uno acepta, el otro también.
final _patron = RegExp(r'^(-?)(\d{1,8})(?:\.(\d{1,2}))?$');

/// Value Object Monto (Doc 2), en soles (PEN, única moneda del MVP).
///
/// **Céntimos enteros, como en el backend.** Un `double` arrastra error
/// binario (`0.1 + 0.2 != 0.3`) y la app suma precios para mostrar
/// `precio_total` y `saldo_pendiente` sin conexión; si sumara distinto que el
/// servidor, el saldo "saltaría" al sincronizar.
///
/// **No restringe el signo** (Doc 2): un saldo pendiente puede ser negativo
/// (saldo a favor del cliente). Cada entidad pone su propia regla.
class Monto implements Comparable<Monto> {
  const Monto._(this.centimos);

  const Monto.desdeCentimos(this.centimos);

  static const cero = Monto._(0);

  final int centimos;

  /// Acepta el número del JSON o un texto tecleado. Un tercer decimal se
  /// **rechaza, no se redondea** (Doc 5, `MONTO_INVALIDO`): redondear dinero
  /// en silencio esconde un error.
  factory Monto.desde(Object valor) {
    if (valor is double && !valor.isFinite) {
      throw const ValorInvalido('MONTO_INVALIDO', 'El monto no es un número.');
    }
    if (valor is! num && valor is! String) {
      throw const ValorInvalido('MONTO_INVALIDO', 'El monto no es un número.');
    }
    // `double.toString()` no redondea (20.5 → "20.5"); 0.1 + 0.2 da
    // "0.30000000000000004" y se rechaza, que es lo correcto.
    final texto = valor.toString().trim();
    final partes = _patron.firstMatch(texto);
    if (partes == null) {
      throw const ValorInvalido(
        'MONTO_INVALIDO',
        'El monto debe tener hasta 8 dígitos enteros y 2 decimales.',
      );
    }
    final enteros = int.parse(partes.group(2)!);
    final decimales = int.parse((partes.group(3) ?? '').padRight(2, '0'));
    final centimos = enteros * 100 + decimales;
    return Monto._(partes.group(1) == '-' ? -centimos : centimos);
  }

  /// Para el JSON de la API, que usa números con 2 decimales (Doc 5).
  num get soles => centimos / 100;

  bool get esNegativo => centimos < 0;
  bool get esCero => centimos == 0;

  Monto operator +(Monto otro) => Monto._(centimos + otro.centimos);
  Monto operator -(Monto otro) => Monto._(centimos - otro.centimos);
  bool operator >(Monto otro) => centimos > otro.centimos;
  bool operator <(Monto otro) => centimos < otro.centimos;

  /// "S/ 1,234.50" — formato peruano: coma de miles, punto decimal. Es el
  /// mismo que usan los mensajes del backend ("S/ 30.00").
  String formatear() {
    final absoluto = centimos.abs();
    final enteros = (absoluto ~/ 100).toString();
    final decimales = (absoluto % 100).toString().padLeft(2, '0');
    final conMiles = enteros.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '${esNegativo ? '-' : ''}S/ $conMiles.$decimales';
  }

  @override
  int compareTo(Monto otro) => centimos.compareTo(otro.centimos);

  @override
  bool operator ==(Object other) => other is Monto && other.centimos == centimos;

  @override
  int get hashCode => centimos.hashCode;

  @override
  String toString() => formatear();
}
