/// Plan v3 "Cierre de año" (§18) y su reemplazo, el v3.1 (§19, 5 oct):
/// periodización por semanas desde el lunes en que se activa. Lógica pura:
/// dado el inicio y una fecha, dice en qué semana y fase va, si es descarga y
/// qué toca el día de resistencia.
library;

import 'dates.dart';

/// Marca de las versiones del plan que siguen esta periodización.
const v3Scheme = 'v3';

/// Semanas del bloque hasta el test final.
const v3Weeks = 10;

/// Los dos últimos son del v3.1: bloque 1 (5 semanas) y bloque 2 (3), con la
/// descarga en medio.
enum V3Phase { acumulacion, descarga, intensificacion, pico, bloque1, bloque2 }

extension V3PhaseLabel on V3Phase {
  String get label => switch (this) {
        V3Phase.acumulacion => 'Acumulación',
        V3Phase.descarga => 'Descarga',
        V3Phase.intensificacion => 'Intensificación',
        V3Phase.pico => 'Pico',
        V3Phase.bloque1 => 'Bloque 1',
        V3Phase.bloque2 => 'Bloque 2',
      };

  /// Qué significa la fase, en una línea para Hoy.
  String get hint => switch (this) {
        V3Phase.acumulacion => 'Aprender los patrones nuevos. RIR 2–3 la primera semana, luego 1–2.',
        V3Phase.descarga => 'Volumen −40 %: una serie menos por ejercicio y sin lastre.',
        V3Phase.intensificacion => 'Lastre y variantes difíciles. RIR 1–2.',
        V3Phase.pico => 'Semana normal; la última baja el volumen hasta el miércoles y cierra con el test.',
        V3Phase.bloque1 => 'Series cerca del fallo (RIR 1–2) con doble progresión.',
        V3Phase.bloque2 => 'Lastre y variantes difíciles. RIR 1–2.',
      };
}

/// Qué se hace el día de resistencia.
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

/// El primer `weekday` en `date` o después.
DateTime nextWeekday(DateTime date, int weekday) {
  final d = dateOnly(date);
  return addDays(d, (weekday - d.weekday + 7) % 7);
}

// ---------------------------------------------------------------------------
// Plan v3.1 (§19). Reemplaza la semana tipo y el calendario del v3: piernas
// el miércoles (a ~72 h de los partidos), una sola sesión metabólica (el
// viernes) y 9 semanas: bloque 1 de 5, descarga, bloque 2 de 3 y pruebas el
// viernes de la semana 9 (11 dic si se empieza el 12 oct).
// ---------------------------------------------------------------------------

const v31Scheme = 'v3.1';
const v31Weeks = 9;

/// Versiones con periodización por semanas (v3 o v3.1).
bool isBlockScheme(String? scheme) => scheme == v3Scheme || scheme == v31Scheme;

V3Phase v31Phase(int week) => switch (week) {
      <= 5 => V3Phase.bloque1,
      6 => V3Phase.descarga,
      _ => V3Phase.bloque2,
    };

/// Semana de descarga del v3.1: mitad de series, misma intensidad, sin
/// lastre extra.
bool v31ReducedVolume(int week) => week == 6;

/// Viernes de pruebas: Cindy, máximo de dominadas estrictas y L-sit máximo.
DateTime v31TestDate(DateTime start) => addDays(dateOnly(start), (v31Weeks - 1) * 7 + 4);

/// Sábados de medición en ayunas: abdomen cada 2 semanas (17 oct, 31 oct,
/// 14 nov, 28 nov y 12 dic) y medidas completas el 14 nov y el 12 dic (§19.4).
List<DateTime> v31MeasurementDates(DateTime start) =>
    [for (final week in [1, 3, 5, 7, 9]) addDays(dateOnly(start), (week - 1) * 7 + 5)];

/// Las dos mediciones completas (las demás son solo abdomen).
List<DateTime> v31FullMeasurementDates(DateTime start) =>
    [addDays(dateOnly(start), 4 * 7 + 5), addDays(dateOnly(start), 8 * 7 + 5)];

/// Próxima medición del v3.1 desde `today` (incluido). null si ya pasó la
/// última.
DateTime? v31NextMeasurement(DateTime start, DateTime today) {
  for (final d in v31MeasurementDates(start)) {
    if (!d.isBefore(dateOnly(today))) return d;
  }
  return null;
}

/// El viernes del v3.1 (§19.1): mientras no salgan 10 rondas limpias es el
/// circuito de progresión (null). Después alterna Cindy y Tabata de bajo
/// impacto, empezando por Cindy el primer viernes tras las 10 limpias. Cindy
/// es prueba la primera vez (línea base) y cada 4 semanas; el viernes de
/// pruebas siempre es Cindy.
({ResistanceMode mode, bool cindyTest})? v31Friday({
  required DateTime date,
  required DateTime testDate,
  DateTime? cleanTen,
}) {
  final day = dateOnly(date);
  if (day == dateOnly(testDate)) return (mode: ResistanceMode.cindy, cindyTest: true);
  if (cleanTen == null) return null;
  final first = nextWeekday(addDays(dateOnly(cleanTen), 1), DateTime.friday);
  if (day.isBefore(first)) return null;
  final n = daysBetween(first, day) ~/ 7;
  return n.isEven
      ? (mode: ResistanceMode.cindy, cindyTest: n % 4 == 0)
      : (mode: ResistanceMode.tabata, cindyTest: false);
}

/// Resumen de un día dentro del bloque, para Hoy y el cronómetro.
class V3Day {
  const V3Day({
    this.scheme = v3Scheme,
    required this.week,
    required this.phase,
    required this.reducedVolume,
    required this.testDate,
    this.resistance,
    this.cindyTest = false,
    this.burpees,
  });

  final String scheme;
  final int week;
  final V3Phase phase;
  final bool reducedVolume;
  final DateTime testDate;

  /// Qué toca el día de resistencia (miércoles del v3, viernes del v3.1).
  /// En el v3.1 es null mientras el viernes siga siendo el circuito de
  /// progresión y en los demás días.
  final ResistanceMode? resistance;

  /// Cindy de prueba (línea base o la de cada 4 semanas).
  final bool cindyTest;

  /// EMOM de burpees del viernes (solo v3): (minutos, burpees por minuto).
  final (int, int)? burpees;

  bool get isV31 => scheme == v31Scheme;
  int get totalWeeks => isV31 ? v31Weeks : v3Weeks;
  String get title => isV31 ? 'Plan v3.1' : 'Cierre de año';

  /// Qué pide la semana, en una línea.
  String get hint {
    if (!isV31) return phase.hint;
    if (phase == V3Phase.descarga) return 'Descarga: mitad de series, misma intensidad, sin lastre extra.';
    if (week == 1) return 'Semana 1: RIR 2–3 para aprender los patrones nuevos.';
    return phase.hint;
  }

  /// Nota que va a la sesión cuando el volumen baja.
  String get deloadNote => isV31
      ? 'Semana $week del v3.1: descarga (mitad de series, sin lastre extra)'
      : phase == V3Phase.descarga
          ? 'Semana $week del v3: descarga (una serie menos, sin lastre)'
          : 'Semana $week del v3: volumen −30 % antes del test';
}

/// `cleanTen`: fecha de la primera progresión de 10 rondas limpias; decide el
/// viernes del v3.1.
V3Day? v3Day(DateTime start, DateTime date, {String scheme = v3Scheme, DateTime? cleanTen}) {
  final week = v3WeekIndex(start, date);
  if (week == null) return null;
  if (scheme == v31Scheme) {
    final testDate = v31TestDate(start);
    final friday =
        date.weekday == DateTime.friday ? v31Friday(date: date, testDate: testDate, cleanTen: cleanTen) : null;
    return V3Day(
      scheme: scheme,
      week: week,
      phase: v31Phase(week),
      reducedVolume: v31ReducedVolume(week),
      testDate: testDate,
      resistance: friday?.mode,
      cindyTest: friday?.cindyTest ?? false,
    );
  }
  return V3Day(
    week: week,
    phase: v3Phase(week),
    reducedVolume: v3ReducedVolume(week, date.weekday),
    testDate: v3TestDate(start),
    resistance: v3Resistance(week),
    burpees: v3Burpees(week),
  );
}
