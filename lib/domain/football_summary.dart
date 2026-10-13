import 'recovery.dart';

/// Resumen de todos los partidos de un día. El RPE desconocido no se inventa;
/// la carga estimada conserva el fallback del core existente.
class FootballDaySummary {
  FootballDaySummary(DateTime day, Iterable<({int minutes, int? intensity, int format})> games)
      : games = List.unmodifiable(games), date = day;

  final DateTime date;
  final List<({int minutes, int? intensity, int format})> games;
  int get count => games.length;
  int get minutes => games.fold(0, (sum, game) => sum + game.minutes);
  int get load => games.fold(0, (sum, game) => sum + LoadItem(
      date: date, minutes: game.minutes, effort: game.intensity, isFootball: true).load);
  bool get estimated => games.any((game) => game.intensity == null);
  double? get weightedRpe {
    final known = games.where((game) => game.intensity != null && game.minutes > 0);
    final duration = known.fold(0, (sum, game) => sum + game.minutes);
    return duration == 0 ? null : known.fold(0, (sum, game) => sum + game.minutes * game.intensity!) / duration;
  }
  String get formatsLabel {
    final formats = games.map((game) => game.format).toSet().toList()..sort();
    return formats.length > 1 ? 'Formatos mixtos (${formats.join(' y ')})'
        : formats.isEmpty ? 'Sin partidos' : 'Fútbol ${formats.single}';
  }
}
