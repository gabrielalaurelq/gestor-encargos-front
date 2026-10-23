import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_encargos/features/clientes/domain/cliente.dart';
import 'package:gestor_encargos/features/encargos/domain/encargo.dart';
import 'package:gestor_encargos/features/encargos/presentation/mensaje_whatsapp.dart';
import 'package:gestor_encargos/shared/domain/monto.dart';
import 'package:gestor_encargos/shared/domain/telefono.dart';

Encargo encargo(String estado, {int saldo = 0, int? numero = 47}) => Encargo(
  id: 'e1',
  numero: numero,
  cliente: Cliente(id: 'ana', nombre: 'Ana García', telefono: Telefono.e164('+51987654321')),
  descripcion: 'Basta de pantalón',
  codigoEstado: estado,
  precioTotal: Monto.desdeCentimos(saldo),
  descuento: Monto.cero,
  saldoPendiente: Monto.desdeCentimos(saldo),
  ubicacionFisica: null,
  notasGenerales: null,
  fechaEntregaPrometida: DateTime.utc(2026, 10, 24),
  fechaEntregaAcordada: DateTime.utc(2026, 10, 24),
  fechaListo: null,
  fechaEntregaReal: null,
);

void main() {
  group('plantillas por estado (Doc 6 v1.1, decisión P1)', () {
    test('listo con saldo: el texto del Caso 12', () {
      expect(
        mensajeWhatsapp(encargo('LISTO', saldo: 3000)),
        'Hola Ana García, su encargo está listo para recoger. Saldo pendiente: S/ 30.00. '
        'Cualquier consulta, escríbame.',
      );
    });

    test('listo sin saldo (o a favor): se omite el saldo', () {
      const sinSaldo =
          'Hola Ana García, su encargo está listo para recoger. Cualquier consulta, escríbame.';
      expect(mensajeWhatsapp(encargo('LISTO')), sinSaldo);
      expect(mensajeWhatsapp(encargo('LISTO', saldo: -500)), sinSaldo);
    });

    test('ingresado o en proceso: el encargo y su fecha de entrega', () {
      const texto =
          'Hola Ana García, le escribo por su encargo #47 (Basta de pantalón). '
          'La entrega es el sábado 24 de octubre. Cualquier consulta, escríbame.';
      expect(mensajeWhatsapp(encargo('INGRESADO')), texto);
      expect(mensajeWhatsapp(encargo('EN_PROCESO')), texto);
    });

    test('entregado con saldo: recuerda lo que queda por pagar', () {
      expect(
        mensajeWhatsapp(encargo('ENTREGADO', saldo: 2000)),
        'Hola Ana García, le recuerdo que quedó un saldo pendiente de S/ 20.00 por su '
        'encargo #47 (Basta de pantalón). Cualquier consulta, escríbame.',
      );
    });

    test('pausado, cancelado o entregado sin saldo: solo saludo y encargo', () {
      const texto = 'Hola Ana García, le escribo por su encargo #47 (Basta de pantalón).';
      expect(mensajeWhatsapp(encargo('PAUSADO')), texto);
      expect(mensajeWhatsapp(encargo('CANCELADO', saldo: 1000)), texto);
      expect(mensajeWhatsapp(encargo('ENTREGADO')), texto);
    });

    test('sin número todavía: no se inventa uno', () {
      expect(
        mensajeWhatsapp(encargo('PAUSADO', numero: null)),
        'Hola Ana García, le escribo por su encargo (Basta de pantalón).',
      );
    });
  });

  test('el enlace: wa.me con el E.164 sin "+" y el texto con %20', () {
    final enlace = enlaceWhatsapp(Telefono.e164('+51987654321'), 'Hola Ana, ¿listo?');

    expect(enlace.toString(), 'https://wa.me/51987654321?text=Hola%20Ana%2C%20%C2%BFlisto%3F');
    expect(enlace.queryParameters['text'], 'Hola Ana, ¿listo?');
  });

  test('un número de otro país funciona igual (PRD 9)', () {
    final enlace = enlaceWhatsapp(Telefono.e164('+34612345678'), 'Hola');

    expect(enlace.path, '/34612345678');
  });
}
