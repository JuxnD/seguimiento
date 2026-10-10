/// La ronda de Cindy: 5 dominadas, 10 flexiones, 15 sentadillas.
const cindyRound = [('Dominadas', 5), ('Flexiones', 10), ('Sentadillas', 15)];

/// Reparte las repeticiones de la ronda a medias en orden: primero las
/// dominadas, luego flexiones, luego sentadillas.
List<(String, int)> splitPartialRound(int reps) {
  final out = <(String, int)>[];
  var left = reps;
  for (final (name, n) in cindyRound) {
    if (left <= 0) break;
    final take = left < n ? left : n;
    out.add((name, take));
    left -= take;
  }
  return out;
}

int get cindyRepsPerRound =>
    cindyRound.fold(0, (total, item) => total + item.$2);
