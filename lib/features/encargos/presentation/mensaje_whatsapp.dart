import '../../../shared/domain/monto.dart';
import '../../../shared/domain/telefono.dart';
import '../../../shared/presentation/formato_fecha.dart';
import '../domain/encargo.dart';
import '../domain/estado_encargo.dart';

/// El mensaje pre-redactado de "Avisar por WhatsApp" (PRD módulo 9; Doc 6
/// v1.1, plantillas decididas por el usuario en el S5c). De "usted", como el
/// Caso 12; el negociante puede editarlo en WhatsApp antes de enviar.
///
/// - Listo: el texto del Caso 12; sin saldo, se omite esa frase.
/// - Ingresado / En proceso: el encargo y su fecha de entrega.
/// - Entregado con saldo: recordatorio de lo que queda por pagar.
/// - Pausado, Cancelado o Entregado sin saldo: solo el saludo y el encargo;
///   el negociante completa.
String mensajeWhatsapp(Encargo encargo) {
  final saludo = 'Hola ${encargo.cliente?.nombre ?? ''}'.trimRight();
  final saldo = encargo.saldoPendiente;
  final debe = saldo > Monto.cero;
  final numero = encargo.numero == null ? '' : ' #${encargo.numero}';
  final cual = 'su encargo$numero (${encargo.descripcion})';
  const cierre = 'Cualquier consulta, escríbame.';
  return switch (encargo.estado) {
    EstadoEncargo.listo => [
      '$saludo, su encargo está listo para recoger.',
      if (debe) 'Saldo pendiente: ${saldo.formatear()}.',
      cierre,
    ].join(' '),
    EstadoEncargo.ingresado || EstadoEncargo.enProceso =>
      '$saludo, le escribo por $cual. La entrega es el '
          '${formatearDiaLargo(encargo.fechaEntregaAcordada)}. $cierre',
    EstadoEncargo.entregado when debe =>
      '$saludo, le recuerdo que quedó un saldo pendiente de ${saldo.formatear()} '
          'por $cual. $cierre',
    _ => '$saludo, le escribo por $cual.',
  };
}

/// `https://wa.me/51987654321?text=…`: el teléfono ya está en E.164, solo se
/// quita el `+` (PRD módulo 9, casos extremos). El texto va con `%20`, como
/// documenta WhatsApp (`Uri.https` pondría `+` en los espacios).
Uri enlaceWhatsapp(Telefono telefono, String mensaje) => Uri.parse(
  'https://wa.me/${telefono.valor.replaceFirst('+', '')}?text=${Uri.encodeComponent(mensaje)}',
);
