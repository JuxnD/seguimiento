/// Búsqueda tolerante para listas cortas escritas a mano (alimentos,
/// ejercicios): sin mayúsculas, sin tildes y por palabras en cualquier orden.
/// "platano" encuentra "Plátano"; "pollo pechuga" encuentra "Pechuga de pollo".
library;

const _folds = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Minúsculas y sin diacríticos.
String foldText(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    out.write(_folds[ch] ?? ch);
  }
  return out.toString();
}

/// true si cada palabra de la consulta aparece en el texto. Consulta vacía:
/// todo coincide.
bool matchesQuery(String text, String query) {
  final haystack = foldText(text);
  final words = foldText(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.every(haystack.contains);
}
