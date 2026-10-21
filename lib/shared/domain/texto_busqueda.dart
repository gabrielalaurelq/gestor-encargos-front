const _sinTilde = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', //
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', //
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', //
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', //
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', //
  'ñ': 'n', 'ç': 'c',
};

/// La forma de un texto con la que se busca y se ordena (PRD módulo 1, Caso 8:
/// búsqueda "tolerante"): minúsculas, sin tildes, la ñ como n y los espacios
/// colapsados. "María  Núñez" → "maria nunez".
///
/// Solo para comparar: lo que se muestra es siempre el texto original. SQLite
/// no sabe quitar tildes, así que esta forma se guarda en una columna aparte
/// (ej. `clientes.nombre_busqueda`), calculada al escribir en local y al bajar.
String normalizarBusqueda(String texto) {
  final minusculas = texto.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  final resultado = StringBuffer();
  for (final caracter in minusculas.split('')) {
    resultado.write(_sinTilde[caracter] ?? caracter);
  }
  return resultado.toString();
}
