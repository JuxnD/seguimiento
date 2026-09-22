/// Fechas como día local `YYYY-MM-DD` y horas `HH:mm`. Se evita guardar
/// DateTime con zona para que un día registrado nunca cambie de fecha.
library;

String pad2(int v) => v.toString().padLeft(2, '0');

String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${pad2(d.month)}-${pad2(d.day)}';

DateTime parseDay(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Suma días de calendario (seguro frente a cambios de horario).
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String timeKey(int hour, int minute) => '${pad2(hour)}:${pad2(minute)}';

/// Semana anclada a la fecha de inicio del perfil, no a la semana calendario.
/// Semana 1 = [inicio, inicio + 6].
class WeekRange {
  const WeekRange(this.index, this.start, this.end);

  final int index;
  final DateTime start;

  /// Inclusivo.
  final DateTime end;

  bool contains(DateTime d) => !d.isBefore(start) && !d.isAfter(end);

  List<DateTime> get days => [for (var i = 0; i <= daysBetween(start, end); i++) addDays(start, i)];
}

int weekIndexFor(DateTime programStart, DateTime date) => (daysBetween(programStart, date) / 7).floor() + 1;

WeekRange weekRange(DateTime programStart, int index) {
  final start = addDays(programStart, (index - 1) * 7);
  return WeekRange(index, start, addDays(start, 6));
}

WeekRange weekContaining(DateTime programStart, DateTime date) =>
    weekRange(programStart, weekIndexFor(programStart, date));

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// `18 sep`
String formatShort(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// `18 sep 2026`
String formatLong(DateTime d) => '${formatShort(d)} ${d.year}';

/// 1 = lunes … 7 = domingo (igual que DateTime.weekday).
String weekdayShort(int weekday) => _weekdays[weekday - 1];

String weekdayLong(int weekday) => const [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ][weekday - 1];

/// `20:00`, `1:02:03`.
String formatDuration(int totalSec) {
  final s = totalSec.abs();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final sign = totalSec < 0 ? '-' : '';
  return h > 0 ? '$sign$h:${pad2(m)}:${pad2(sec)}' : '$sign$m:${pad2(sec)}';
}

/// Acepta `20` (minutos), `20:00`, `1:02:03`. Devuelve segundos o null.
int? parseDuration(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length > 3) return null;
  final nums = parts.map(int.tryParse).toList();
  if (nums.any((n) => n == null || n < 0)) return null;
  return switch (nums.length) {
    1 => nums[0]! * 60,
    2 => nums[0]! * 60 + nums[1]!,
    _ => nums[0]! * 3600 + nums[1]! * 60 + nums[2]!,
  };
}
