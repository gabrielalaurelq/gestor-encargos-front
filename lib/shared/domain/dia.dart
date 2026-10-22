// Días de calendario del negocio, como `DateTime` UTC a medianoche: así se
// comparan y se formatean sin que la zona del teléfono los corra un día.

/// Las fechas de hecho de la API (`fecha_entrega_acordada`, `fecha_listo`…)
/// son `AAAA-MM-DD`, sin hora (Doc 5).
DateTime diaDesdeIso(String aaaaMmDd) {
  final partes = aaaaMmDd.split('-').map(int.parse).toList();
  return DateTime.utc(partes[0], partes[1], partes[2]);
}

/// El día en Lima de un instante (`creado_en`), igual que el backend con
/// `ZONA_NEGOCIO = 'America/Lima'`. Perú no tiene horario de verano: es UTC-5
/// todo el año, así que no hace falta una base de zonas horarias.
DateTime diaDelNegocio(String instanteIso) {
  final lima = DateTime.parse(instanteIso).toUtc().subtract(const Duration(hours: 5));
  return DateTime.utc(lima.year, lima.month, lima.day);
}
