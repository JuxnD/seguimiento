/// Plan v3 "Cierre de año" (§18): periodización de 10 semanas desde el lunes
/// en que se activa. Lógica pura: dado el inicio y una fecha, dice en qué
/// semana y fase va, si es descarga, qué toca el miércoles y cuántos burpees
/// el viernes.
library;

import 'dates.dart';

/// Marca de las versiones del plan que siguen esta periodización.
const v3Scheme = 'v3';

/// Semanas del bloque hasta el test final.
const v3Weeks = 10;

enum V3Phase { acumulacion, descarga, intensificacion, pico }

extension V3PhaseLabel on V3Phase {
  String get label => switch (this) {
        V3Phase.acumulacion => 'Acumulación',
        V3Phase.descarga => 'Descarga',
        V3Phase.intensificacion => 'Intensificación',
        V3Phase.pico => 'Pico',
      };

  /// Qué significa la fase, en una línea para Hoy.
  String get hint => switch (this) {
        V3Phase.acumulacion => 'Aprender los patrones nuevos. RIR 2–3 la primera semana, luego 1–2.',
        V3Phase.descarga => 'Volumen −40 %: una serie menos por ejercicio y sin lastre.',
        V3Phase.intensificacion => 'Lastre y variantes difíciles. RIR 1–2.',
        V3Phase.pico => 'Semana normal; la última baja el volumen hasta el miércoles y cierra con el test.',
      };
}

/// Qué se hace el miércoles de resistencia.
enum ResistanceMode { cindy, tabata, porTiempo }

extension ResistanceModeLabel on ResistanceMode {
  String get label => switch (this) {
        ResistanceMode.cindy => 'Cindy · AMRAP 20 min',
        ResistanceMode.tabata => 'Tabata · 4 bloques de 8 × 20/10',
        ResistanceMode.porTiempo => '10 rondas por tiempo',
      };
}

/// Semana del bloque (1 = la del lunes de inicio). null antes de empezar.
int? v3WeekIndex(DateTime start, DateTime date) {
  final d = daysBetween(dateOnly(start), dateOnly(date));
  return d < 0 ? null : d ~/ 7 + 1;
}

V3Phase v3Phase(int week) => switch (week) {
      <= 3 => V3Phase.acumulacion,
      4 || 8 => V3Phase.descarga,
      <= 7 => V3Phase.intensificacion,
      _ => V3Phase.pico,
    };

/// Una serie menos y sin lastre: semanas 4 y 8 enteras, y la 10 de lunes a
/// miércoles (−30 % antes del test).
bool v3ReducedVolume(int week, int weekday) =>
    week == 4 || week == 8 || (week == v3Weeks && weekday <= DateTime.wednesday);

/// Cindy las semanas impares, Tabata las pares. Las de control cambian: la 4
/// es el test de Cindy y la 8 las 10 rondas por tiempo; la 10 cierra con
/// Cindy el miércoles 16 dic (§18.2, §18.6).
ResistanceMode v3Resistance(int week) => switch (week) {
      4 || 10 => ResistanceMode.cindy,
      8 => ResistanceMode.porTiempo,
      _ => week.isOdd ? ResistanceMode.cindy : ResistanceMode.tabata,
    };

/// EMOM de burpees del viernes: (minutos, burpees por minuto). null en
/// descarga y en la semana del test (§18.10).
(int, int)? v3Burpees(int week) => switch (week) {
      <= 3 => (6, 6),
      4 || 8 => null,
      <= 7 => (8, 8),
      9 => (10, 10),
      _ => null,
    };

/// Viernes de la semana 10: el test final (18 dic si se empieza el 12 oct).
DateTime v3TestDate(DateTime start) => addDays(dateOnly(start), (v3Weeks - 1) * 7 + 4);

/// Viernes de medición en ayunas: semanas 4 y 8 (6 nov y 4 dic).
List<DateTime> v3MeasurementDates(DateTime start) =>
    [addDays(dateOnly(start), 3 * 7 + 4), addDays(dateOnly(start), 7 * 7 + 4)];

/// El lunes siguiente a `date` (o `date` si ya es lunes): el v3 arranca en
/// lunes.
DateTime nextMonday(DateTime date) {
  final d = dateOnly(date);
  return d.weekday == DateTime.monday ? d : addDays(d, 8 - d.weekday);
}

/// Resumen de un día dentro del bloque, para Hoy y el cronómetro.
class V3Day {
  const V3Day({required this.week, required this.phase, required this.reducedVolume, required this.testDate});

  final int week;
  final V3Phase phase;
  final bool reducedVolume;
  final DateTime testDate;

  ResistanceMode get resistance => v3Resistance(week);
  (int, int)? get burpees => v3Burpees(week);
}

V3Day? v3Day(DateTime start, DateTime date) {
  final week = v3WeekIndex(start, date);
  if (week == null) return null;
  return V3Day(
    week: week,
    phase: v3Phase(week),
    reducedVolume: v3ReducedVolume(week, date.weekday),
    testDate: v3TestDate(start),
  );
}
