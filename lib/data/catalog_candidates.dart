import '../domain/search.dart';
import 'database.dart';

/// Search the entire catalog, then bound transport. Input order retains
/// favorites/recent use ties from foodsForSuggestions, not database ID order.
List<FoodRow> catalogCandidates(String text, List<FoodRow> foods,
    {int limit = 200}) {
  final phrase = foldText(text);
  final words =
      phrase.split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 2).toSet();
  int score(FoodRow f) {
    final name = foldText(f.name);
    final aliases = catalogAliases[name] ?? const <String>[];
    final names = [name, ...aliases];
    return names.fold<int>(0, (best, candidate) {
      final full = phrase.contains(candidate) ? 1000 + candidate.length : 0;
      final overlap =
          candidate.split(RegExp(r'[^a-z0-9]+')).where(words.contains).length *
              20;
      final rank = full + overlap + (f.favorite ? 10 : 0);
      return rank > best ? rank : best;
    });
  }

  final ranked = [
    for (var i = 0; i < foods.length; i++) (i, foods[i], score(foods[i]))
  ]..sort((a, b) {
      final result = b.$3.compareTo(a.$3);
      return result == 0 ? a.$1.compareTo(b.$1) : result;
    });
  return ranked.take(limit.clamp(0, 200)).map((r) => r.$2).toList();
}

/// Aliases identify the same food, never similar recipes or a powder as milk.
const catalogAliases = <String, List<String>>{
  'huevo (unidad)': ['huevo', 'huevos'],
  'leche entera': ['leche'],
  'leche klim en polvo': ['klim', 'leche klim'],
  'nestum': ['cereal nestum'],
  'frijoles cocidos': ['frijoles', 'frijol'],
};

/// Recipe names to ask/estimate, not zero-macro foods or verified catalog rows.
const recipeCandidates = [
  'arroz chino',
  'arroz frito',
  'arroz con pollo',
  'arepa',
  'empanada',
  'sancocho',
  'ajiaco',
  'bandeja paisa',
  'calentado',
  'pollo asado',
  'milo'
];
