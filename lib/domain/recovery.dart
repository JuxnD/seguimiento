/// Recuperación y carga (§16.15, §19.6): momentos del pesaje, molestias por
/// zona, pulso en reposo, carga del día (RPE × minutos) y cuándo conviene el
/// plan B de solo torso. Lógica pura.
library;

import 'dates.dart';

// ---------------------------------------------------------------------------
// Pesaje
// ---------------------------------------------------------------------------

/// Momento de un pesaje. Solo en ayunas entra en el promedio semanal; el
/// resto es referencia (antes y después del fútbol dan la tasa de sudor).
enum WeighMoment { ayunas, antesDormir, antesFutbol, despuesFutbol, otro }

extension WeighMomentLabel on WeighMoment {
  String get label => switch (this) {
        WeighMoment.ayunas => 'En ayunas',
        WeighMoment.antesDormir => 'Antes de dormir',
        WeighMoment.antesFutbol => 'Antes del fútbol',
        WeighMoment.despuesFutbol => 'Después del fútbol',
        WeighMoment.otro => 'Otro',
      };

  /// Un día tiene un solo pesaje de estos momentos: registrar otro lo
  /// reemplaza. "Otro" admite varios (después de desayunar, antes de cenar).
  bool get onePerDay => this != WeighMoment.otro;
}

/// Momento de un pesaje guardado; los anteriores al esquema 17 no lo tienen.
WeighMoment weighMomentOf(String? raw, {required bool fasted}) {
  for (final m in WeighMoment.values) {
    if (m.name == raw) return m;
  }
  return fasted ? WeighMoment.ayunas : WeighMoment.otro;
}

// ---------------------------------------------------------------------------
// Molestias
// ---------------------------------------------------------------------------

/// Zonas del registro de molestias, en el orden en que se muestran.
const sorenessZones = [
  'Rodilla',
  'Isquios',
  'Cuádriceps',
  'Gemelo',
  'Cadera o ingle',
  'Espalda baja',
  'Hombro',
  'Codo',
  'Muñeca',
];

/// Zonas que, si molestan, piden quitar piernas.
const legZones = {'Rodilla', 'Isquios', 'Cuádriceps', 'Gemelo', 'Cadera o ingle'};

/// Zonas con una molestia que no baja en 3 días o que sube (§16.15): conviene
/// aplazar piernas o el intento de récord. `byDay`: día → zona → nivel.
List<String> persistentSoreness(Map<DateTime, Map<String, int>> byDay, DateTime today) {
  final out = <String>[];
  final d0 = dateOnly(today);
  final days = [addDays(d0, -2), addDays(d0, -1), d0];
  final zones = {for (final d in days) ...?byDay[d]?.keys};
  for (final zone in zones) {
    final levels = [for (final d in days) byDay[d]?[zone]];
    final known = levels.whereType<int>().toList();
    if (known.isEmpty || known.last == 0) continue;
    // Sube respecto a la toma anterior.
    final rising = known.length >= 2 && known.last > known[known.length - 2];
    // Tres días seguidos con molestia y sin bajar.
    final stuck = levels.every((l) => l != null && l > 0) && levels.last! >= levels.first!;
    if (rising || stuck) out.add(zone);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Pulso en reposo
// ---------------------------------------------------------------------------

/// Cuánto por encima de la media tiene que estar el pulso para avisar.
const restingHrRiseBpm = 5;

/// Aviso de recuperación baja (§19.6): los últimos 3 días seguidos están al
/// menos 5 lpm por encima de la media de los 7 anteriores. null si no.
String? restingHrWarning(Map<DateTime, int> byDay, DateTime today) {
  final d0 = dateOnly(today);
  final last3 = [for (var i = 2; i >= 0; i--) byDay[addDays(d0, -i)]];
  if (last3.any((v) => v == null)) return null;
  final before = [for (var i = 3; i < 10; i++) byDay[addDays(d0, -i)]].whereType<int>().toList();
  if (before.length < 3) return null;
  final mean = before.reduce((a, b) => a + b) / before.length;
  if (last3.every((v) => v! >= mean + restingHrRiseBpm)) {
    return 'Pulso en reposo 3 días seguidos ${last3.last! - mean.round()} lpm por encima de tu media '
        '(${mean.round()}): recuperación baja, considera la versión ligera.';
  }
  return null;
}

/// Media de 7 días del pulso en reposo. null sin lecturas.
double? restingHrAverage(Map<DateTime, int> byDay, DateTime today) {
  final d0 = dateOnly(today);
  final values = [for (var i = 0; i < 7; i++) byDay[addDays(d0, -i)]].whereType<int>().toList();
  return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
}

// ---------------------------------------------------------------------------
// Carga
// ---------------------------------------------------------------------------

/// Algo que cuenta como carga en un día: una sesión (RPE × minutos) o un
/// partido (intensidad × minutos).
class LoadItem {
  const LoadItem({required this.date, required this.minutes, this.effort, this.isFootball = false});

  final DateTime date;
  final int minutes;

  /// RPE o intensidad percibida (1–10). null = no se anotó.
  final int? effort;
  final bool isFootball;

  /// Sin esfuerzo anotado se toma 6 (moderado): mejor contar algo que nada.
  int get load => minutes * (effort ?? 6);
  bool get intense => (effort ?? 0) >= 7;
}

/// Carga alta de un día (RPE × min). Un partido de 90 min a 8 son 720.
const highDayLoad = 600;

/// Cómo viene el cuerpo hoy.
class LoadReading {
  const LoadReading({
    required this.todayLoad,
    required this.todayCount,
    required this.intenseStreak,
  });

  final int todayLoad;

  /// Sesiones y partidos de hoy.
  final int todayCount;

  /// Días seguidos (hasta hoy, o hasta ayer si hoy no hay nada) con algo
  /// intenso.
  final int intenseStreak;

  bool get twoToday => todayCount >= 2;
  bool get highToday => todayLoad >= highDayLoad;
  bool get threeIntense => intenseStreak >= 3;

  /// Otra sesión hoy pide confirmación.
  bool get warnAnotherSession => twoToday || highToday || threeIntense;

  /// Por qué conviene no entrenar otra vez.
  String get reason => twoToday
      ? 'Ya entrenaste dos veces hoy. Recuperar ahora te deja mejor para el viernes.'
      : threeIntense
          ? '$intenseStreak días seguidos intensos. Recuperar ahora te deja mejor para el viernes.'
          : 'La carga de hoy ya es alta ($todayLoad). Recuperar ahora te deja mejor para el viernes.';
}

LoadReading loadReading(List<LoadItem> items, DateTime today) {
  final d0 = dateOnly(today);
  final todayItems = items.where((i) => dateOnly(i.date) == d0).toList();
  bool intenseOn(DateTime d) => items.any((i) => dateOnly(i.date) == d && i.intense);
  var streak = 0;
  var day = intenseOn(d0) ? d0 : addDays(d0, -1);
  while (intenseOn(day)) {
    streak++;
    day = addDays(day, -1);
  }
  return LoadReading(
    todayLoad: todayItems.fold(0, (a, i) => a + i.load),
    todayCount: todayItems.length,
    intenseStreak: streak,
  );
}

// ---------------------------------------------------------------------------
// Plan B: solo torso
// ---------------------------------------------------------------------------

/// Ejercicios que cargan la pierna: con 3 días intensos seguidos o molestia en
/// la pierna se quitan hasta 48 h después (§16.15).
const legExercises = {
  'Sentadillas',
  'Sentadilla búlgara',
  'Peso muerto a una pierna con mochila',
  'Nórdico (isquios)',
  'Gemelos a una pierna en escalón',
  'Salto vertical',
  'Salto largo',
  'Salto de patinador',
  'Aceleración 10–20 m',
  'Carga de maleta con mochila',
  'Carga abrazada al pecho',
  'Progresión de pistol',
  'Puente de glúteo a una pierna',
};

/// Plan B de referencia (mar 6 oct): solo torso, todo a RIR 2.
/// (nombre, series, reps mín, reps máx, segundos, por lado).
const planBTorso = [
  ('Dominadas', 3, 8, 8, null, false),
  ('Flexiones', 4, 12, 12, null, false),
  ('Pike push-up', 3, 6, 8, null, false),
  ('Remo invertido (mesa)', 3, 10, 10, null, false),
  ('Plancha lateral', 2, null, null, 30, true),
  ('Hollow body hold', 2, null, null, 20, false),
];

/// ¿Conviene el plan B hoy? Con 3 días intensos seguidos o molestia en una
/// zona de pierna hoy o ayer, si el día trae pierna.
bool suggestPlanB({
  required bool dayHasLegs,
  required LoadReading load,
  required Map<DateTime, Map<String, int>> soreness,
  required DateTime today,
}) {
  if (!dayHasLegs) return false;
  final d0 = dateOnly(today);
  final legSore = [d0, addDays(d0, -1)].any(
      (d) => (soreness[d] ?? const {}).entries.any((e) => legZones.contains(e.key) && e.value >= 3));
  return load.threeIntense || legSore;
}

// ---------------------------------------------------------------------------
// Hoja de ruta de habilidades (§19.8)
// ---------------------------------------------------------------------------

class Skill {
  const Skill(this.id, this.name, this.criterion, this.fromMonth, this.toMonth, {this.prereq});

  final String id;
  final String name;
  final String criterion;

  /// Plazo orientativo desde octubre de 2026, en meses.
  final int fromMonth;
  final int toMonth;

  /// Lo que conviene tener antes de entrenarla.
  final String? prereq;

  String get window => toMonth >= 24 && fromMonth >= 24
      ? '${fromMonth ~/ 12}–${toMonth ~/ 12} años'
      : '$fromMonth–$toMonth meses';
}

/// Inicio de la hoja de ruta: octubre de 2026.
final skillsStart = DateTime(2026, 10, 1);

const skillRoadmap = [
  Skill('elbow_lever', 'Elbow lever', '10 s', 0, 3),
  Skill('l_sit', 'L-sit', '20 s', 0, 3),
  Skill('handstand', 'Pino libre', '30 s', 3, 6),
  Skill('v_sit', 'V-sit', '5 s', 3, 6),
  Skill('muscle_up', 'Muscle-up en barra', '3 limpios', 3, 9,
      prereq: '12 dominadas estrictas y 15 fondos'),
  Skill('wall_hspu', 'HSPU contra la pared', '5 completos', 6, 12),
  Skill('tuck_planche', 'Tuck planche', '10 s', 6, 12, prereq: 'inclinación de planche 3 × 30 s (§19.7)'),
  Skill('tuck_front_lever', 'Tuck front lever', '10 s', 6, 12),
  Skill('straddle_front_lever', 'Front lever straddle', '5 s', 12, 18,
      prereq: '10 dominadas con 10 kg'),
  Skill('impossible_dip', 'Fondo imposible', '3 reps', 12, 18),
  Skill('free_hspu', 'HSPU libre', '3 reps', 12, 24),
  Skill('straddle_planche', 'Planche straddle', '5 s', 12, 24),
  Skill('full_planche', 'Full planche', '5 s', 24, 60),
  Skill('full_front_lever', 'Full front lever', '5 s', 24, 60),
];

/// Ventana estimada ("mar 2027 – jul 2027") de una habilidad.
(DateTime, DateTime) skillWindow(Skill s) => (
      DateTime(skillsStart.year, skillsStart.month + s.fromMonth),
      DateTime(skillsStart.year, skillsStart.month + s.toMonth),
    );
