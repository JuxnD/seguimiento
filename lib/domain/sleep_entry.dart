// Horas en cama (§16.19, 9 oct): los botones llegaban a 9 h y el 7 oct el
// usuario durmió 10 h 11 min. Se añaden 9,5 y 10, y "Otro" para escribirlo.

/// Botones de un toque.
const sleepOptions = [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0];

/// Lo que admite la base (`sleep_logs.hours` entre 0 y 16).
const maxSleepHours = 16.0;

/// "10,2", "10.2", "10:11", "10h11", "10 h 11 min" o "10 h" → horas con
/// decimales (10 h 11 min = 10,18). null si no se entiende o se sale de 0–16.
double? parseSleepHours(String raw) {
  final s = raw.trim().toLowerCase().replaceAll(',', '.');
  if (s.isEmpty) return null;
  double? hours;
  final hm = RegExp(r'^(\d{1,2})\s*(?::|h)\s*(\d{1,2})?\s*(?:m|min)?$').firstMatch(s);
  if (hm != null) {
    final h = int.parse(hm.group(1)!);
    final m = hm.group(2) == null ? 0 : int.parse(hm.group(2)!);
    if (m >= 60) return null;
    hours = h + m / 60;
  } else {
    hours = double.tryParse(s);
  }
  if (hours == null || hours <= 0 || hours > maxSleepHours) return null;
  return (hours * 100).roundToDouble() / 100;
}

/// ¿Es uno de los botones? Si no, se muestra aparte como "Otro".
bool isSleepOption(double? hours) => hours != null && sleepOptions.contains(hours);

/// 10,18 → "10 h 11 min"; 10 → "10 h". Para lo escrito con "Otro".
String formatSleepHours(double hours) {
  final total = (hours * 60).round();
  final h = total ~/ 60;
  final m = total % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

// ---------------------------------------------------------------------------
// Hora de acostarse y de despertar (plan 040, §16.26)
// ---------------------------------------------------------------------------

/// Procedencia de una noche anotada. null = de antes de registrarlo.
const sleepSourceManual = 'manual';

/// Anotada a mano desde el reloj (no se importa nada del reloj).
const sleepSourceClock = 'clock';

/// Venía del reloj y se corrigió a mano (p. ej., el reloj se descargó).
const sleepSourceEditManual = 'edit_manual';

/// Procedencia después de una edición a mano: lo que venía del reloj y se
/// corrige queda como corregido; lo marcado como "del reloj" queda así.
String sleepSourceAfterEdit(String? previous, {required bool fromClock}) {
  if (fromClock) return sleepSourceClock;
  if (previous == sleepSourceClock || previous == sleepSourceEditManual) return sleepSourceEditManual;
  return sleepSourceManual;
}

/// "anotado del reloj" / "corregido a mano"; null para lo manual o lo viejo.
String? sleepSourceLabel(String? source) => switch (source) {
      sleepSourceClock => 'anotado del reloj',
      sleepSourceEditManual => 'corregido a mano',
      _ => null,
    };

/// La noche que termina la mañana de `day`: despierta ese día a la hora
/// `wake`; se acostó ese mismo día si la hora es anterior a la de despertar
/// (siesta larga, madrugada) o el día anterior si no (cruza la medianoche).
({DateTime start, DateTime wake}) sleepWindow(DateTime day, (int, int) start, (int, int) wake) {
  final wakeAt = DateTime(day.year, day.month, day.day, wake.$1, wake.$2);
  var startAt = DateTime(day.year, day.month, day.day, start.$1, start.$2);
  if (!startAt.isBefore(wakeAt)) startAt = startAt.subtract(const Duration(days: 1));
  return (start: startAt, wake: wakeAt);
}

/// Horas entre acostarse y despertar, a dos decimales. null si no despertó
/// después de acostarse o pasa de 16 h.
double? hoursBetween(DateTime start, DateTime wake) {
  if (!wake.isAfter(start)) return null;
  final hours = wake.difference(start).inMinutes / 60;
  if (hours <= 0 || hours > maxSleepHours) return null;
  return (hours * 100).roundToDouble() / 100;
}
