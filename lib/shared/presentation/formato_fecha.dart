const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _mesesLargos = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];
const _diasLargos = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

/// "jueves 23 de octubre": la fecha de hoy en la cabecera del Dashboard
/// (Doc 6, wireframe).
String formatearDiaLargo(DateTime dia) =>
    '${_diasLargos[dia.weekday - 1]} ${dia.day} de ${_mesesLargos[dia.month - 1]}';

/// "24 oct 2026", o "vie 24 oct" con [conDiaSemana] y sin [conAnio]: corto y
/// en español, sin depender del idioma del teléfono. [dia] es un día del
/// negocio (ver `dia.dart`).
String formatearDia(DateTime dia, {bool conDiaSemana = false, bool conAnio = true}) {
  final partes = [
    if (conDiaSemana) _dias[dia.weekday - 1],
    '${dia.day}',
    _meses[dia.month - 1],
    if (conAnio) '${dia.year}',
  ];
  return partes.join(' ');
}
