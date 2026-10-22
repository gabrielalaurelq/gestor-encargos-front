// Días de calendario del negocio, como `DateTime` UTC a medianoche: así se
// comparan y se formatean sin que la zona del teléfono los corra un día.

/// Las fechas de hecho de la API (`fecha_entrega_acordada`, `fecha_listo`…)
/// son `AAAA-MM-DD`, sin hora (Doc 5).
DateTime diaDesdeIso(String aaaaMmDd) {
  final partes = aaaaMmDd.split('-').map(int.parse).toList();
  return DateTime.utc(partes[0], partes[1], partes[2]);
}

/// El día como lo espera la API: `AAAA-MM-DD`.
String isoDesdeDia(DateTime dia) =>
    '${dia.year.toString().padLeft(4, '0')}-${dia.month.toString().padLeft(2, '0')}-'
    '${dia.day.toString().padLeft(2, '0')}';

/// El día en Lima de un instante (`creado_en`), igual que el backend con
/// `ZONA_NEGOCIO = 'America/Lima'`. Perú no tiene horario de verano: es UTC-5
/// todo el año, así que no hace falta una base de zonas horarias.
DateTime diaDelNegocio(String instanteIso) => _diaEnLima(DateTime.parse(instanteIso));

/// Hoy en Lima según el reloj del teléfono.
DateTime hoyDelNegocio([DateTime? ahora]) => _diaEnLima(ahora ?? DateTime.now());

DateTime _diaEnLima(DateTime instante) {
  final lima = instante.toUtc().subtract(const Duration(hours: 5));
  return DateTime.utc(lima.year, lima.month, lima.day);
}
