/// Qué notificaciones tocan y cuándo. Lógica pura: decide a qué hora suena
/// cada aviso y con qué texto, sin saber nada del sistema de notificaciones.
library;

import 'dates.dart';
import 'enums.dart';
import 'format.dart';
import 'steps.dart';

/// Tipos de recordatorio. El nombre se persiste, así que no se renombran.
enum ReminderKind {
  sesion,
  sesionSinRegistrar,
  comidaDesayuno,
  comidaMerienda,
  comidaCena,
  proteina,
  medicion,
  descanso,
  calorias,
  comidasSinRegistrar,
  pasos,

  /// Recordatorios que crea el usuario (cuello, estiramientos…). No tienen
  /// fila en `reminders`: cada uno vive en `custom_reminders`.
  personalizado,
}

extension ReminderKindLabel on ReminderKind {
  String get label => switch (this) {
        ReminderKind.sesion => 'Antes de la sesión',
        ReminderKind.sesionSinRegistrar => 'Sesión sin registrar',
        ReminderKind.comidaDesayuno => 'Desayuno',
        ReminderKind.comidaMerienda => 'Merienda',
        ReminderKind.comidaCena => 'Cena',
        ReminderKind.proteina => 'Proteína del día',
        ReminderKind.medicion => 'Medición',
        ReminderKind.descanso => 'Fin del descanso',
        ReminderKind.calorias => 'Calorías del día',
        ReminderKind.comidasSinRegistrar => 'Comidas sin registrar',
        ReminderKind.pasos => 'Pasos del día',
        ReminderKind.personalizado => 'Recordatorio propio',
      };

  String get description => switch (this) {
        ReminderKind.sesion => 'Avisa 15 min antes de la hora de entrenar, con lo que toca ese día',
        ReminderKind.sesionSinRegistrar => 'Si a esa hora no hay sesión guardada en un día de entrenamiento',
        ReminderKind.comidaDesayuno => 'Recordatorio de registrar el desayuno',
        ReminderKind.comidaMerienda => 'Recordatorio de registrar la merienda',
        ReminderKind.comidaCena => 'Recordatorio de registrar la cena',
        ReminderKind.proteina => 'Si a esa hora vas por debajo del mínimo, dice cuánto falta',
        ReminderKind.medicion => 'Cuando se cumple el intervalo desde la última toma, en la mañana',
        ReminderKind.descanso => 'Suena y vibra al terminar el descanso, aunque la app esté en segundo plano',
        ReminderKind.calorias => 'Si a esa hora vas por debajo del umbral, dice cuánto falta para la meta',
        ReminderKind.comidasSinRegistrar =>
          'Si a esa hora falta desayuno, almuerzo o cena, dice cuál (no suena si cerraste el día)',
        ReminderKind.pasos => 'Entre semana, si a esa hora vas por debajo del umbral de pasos',
        ReminderKind.personalizado => 'Cada N días desde la última vez que lo marcaste como hecho',
      };

  /// Los que no se programan por hora del día.
  bool get isScheduled => this != ReminderKind.descanso;
}

/// Configuración de un recordatorio.
class ReminderSetting {
  const ReminderSetting({required this.kind, required this.enabled, this.hour, this.minute, this.threshold});

  final ReminderKind kind;
  final bool enabled;
  final int? hour;
  final int? minute;

  /// Umbral del aviso de proteína (g) o de calorías (kcal).
  final int? threshold;

  String get timeLabel => hour == null ? '—' : timeKey(hour!, minute ?? 0);
}

/// Aviso ya resuelto: cuándo suena y qué dice.
class PlannedNotification {
  const PlannedNotification({
    required this.kind,
    required this.when,
    required this.title,
    required this.body,
    this.customId,
  });

  final ReminderKind kind;
  final DateTime when;
  final String title;
  final String body;

  /// Recordatorio propio del que sale este aviso.
  final int? customId;

  /// Id estable por tipo y día, para poder reprogramar sin duplicar. Los
  /// propios van en su propio rango (100000+), lejos de los fijos (< 12000).
  int get id => customId != null ? 100000 + customId! * 64 + when.day : kind.index * 1000 + when.day * 24 + when.hour;
}

/// Lo que el planificador necesita saber de un día.
class ReminderDay {
  const ReminderDay({
    required this.date,
    required this.type,
    this.planSummary,
    this.hasSession = false,
  });

  final DateTime date;
  final DayType type;

  /// "Circuito 6 rondas", "Bloques — Dominadas 4×6–8".
  final String? planSummary;

  /// Ya hay una sesión registrada ese día.
  final bool hasSession;
}

/// Estado de hoy que cambia el texto o la necesidad de algunos avisos.
class ReminderContext {
  const ReminderContext({
    required this.now,
    required this.days,
    required this.settings,
    this.proteinToday = 0,
    this.proteinMin = 130,
    this.kcalToday = 0,
    this.kcalTarget = 2400,
    this.missingMealsToday = const [],
    this.stepsToday,
    this.stepsTarget = 7500,
    this.custom = const [],
    this.lastMeasurement,
    this.measureIntervalDays = 21,
    this.nextMeasurementDate,
  });

  final DateTime now;

  /// Días a programar, empezando por hoy.
  final List<ReminderDay> days;
  final Map<ReminderKind, ReminderSetting> settings;
  final double proteinToday;
  final int proteinMin;
  final double kcalToday;
  final int kcalTarget;

  /// Comidas principales que faltan hoy; vacío si el día está cerrado.
  final List<MealSlot> missingMealsToday;

  /// Pasos registrados hoy; null = aún no se anotan.
  final int? stepsToday;
  final int stepsTarget;

  /// Recordatorios propios del usuario.
  final List<CustomReminder> custom;
  final DateTime? lastMeasurement;
  final int measureIntervalDays;
  final DateTime? nextMeasurementDate;

  ReminderSetting? setting(ReminderKind kind) => settings[kind];
}

/// Arma todos los avisos futuros. Nunca programa algo en el pasado.
List<PlannedNotification> planReminders(ReminderContext ctx) {
  final out = <PlannedNotification>[];

  for (final day in ctx.days) {
    out.addAll(_sessionReminder(ctx, day));
    out.addAll(_unloggedSession(ctx, day));
    out.addAll(_mealReminders(ctx, day));
    out.addAll(_customReminders(ctx, day));
  }
  out.addAll(_protein(ctx));
  out.addAll(_calories(ctx));
  out.addAll(_missingMeals(ctx));
  out.addAll(_steps(ctx));
  out.addAll(_measurement(ctx));

  return out.where((n) => n.when.isAfter(ctx.now)).toList()
    ..sort((a, b) => a.when.compareTo(b.when));
}

DateTime _at(DateTime day, ReminderSetting s) =>
    DateTime(day.year, day.month, day.day, s.hour ?? 0, s.minute ?? 0);

Iterable<PlannedNotification> _sessionReminder(ReminderContext ctx, ReminderDay day) sync* {
  final s = ctx.setting(ReminderKind.sesion);
  if (s == null || !s.enabled || !day.type.isTraining || day.hasSession) return;
  // 15 minutos antes de la hora de entrenar.
  final when = _at(day.date, s).subtract(const Duration(minutes: 15));
  yield PlannedNotification(
    kind: ReminderKind.sesion,
    when: when,
    title: 'En 15 min: ${day.type.label}',
    body: day.planSummary ?? 'Toca entrenar',
  );
}

Iterable<PlannedNotification> _unloggedSession(ReminderContext ctx, ReminderDay day) sync* {
  final s = ctx.setting(ReminderKind.sesionSinRegistrar);
  if (s == null || !s.enabled || !day.type.isTraining || day.hasSession) return;
  yield PlannedNotification(
    kind: ReminderKind.sesionSinRegistrar,
    when: _at(day.date, s),
    title: 'Sin sesión registrada',
    body: 'Hoy tocaba ${day.type.label.toLowerCase()}. Si entrenaste, regístralo; si no, anótalo igual.',
  );
}

Iterable<PlannedNotification> _mealReminders(ReminderContext ctx, ReminderDay day) sync* {
  const meals = {
    ReminderKind.comidaDesayuno: MealSlot.desayuno,
    ReminderKind.comidaMerienda: MealSlot.merienda,
    ReminderKind.comidaCena: MealSlot.cena,
  };
  for (final entry in meals.entries) {
    final s = ctx.setting(entry.key);
    if (s == null || !s.enabled) continue;
    yield PlannedNotification(
      kind: entry.key,
      when: _at(day.date, s),
      title: 'Registrar ${entry.value.label.toLowerCase()}',
      body: 'Dos toques: abre la app y usa un combo si repetiste lo de siempre.',
    );
  }
}

Iterable<PlannedNotification> _protein(ReminderContext ctx) sync* {
  final s = ctx.setting(ReminderKind.proteina);
  if (s == null || !s.enabled) return;
  final threshold = s.threshold ?? 100;
  // Solo tiene sentido con los datos de hoy: mañana serán otros.
  if (ctx.proteinToday >= threshold) return;
  final missing = (ctx.proteinMin - ctx.proteinToday).round();
  yield PlannedNotification(
    kind: ReminderKind.proteina,
    when: _at(ctx.now, s),
    title: 'Proteína: ${ctx.proteinToday.round()} g',
    body: 'Faltan $missing g para el mínimo de ${ctx.proteinMin} g.',
  );
}

Iterable<PlannedNotification> _calories(ReminderContext ctx) sync* {
  final s = ctx.setting(ReminderKind.calorias);
  if (s == null || !s.enabled) return;
  final threshold = s.threshold ?? 1800;
  if (ctx.kcalToday >= threshold) return;
  final missing = (ctx.kcalTarget - ctx.kcalToday).round();
  yield PlannedNotification(
    kind: ReminderKind.calorias,
    when: _at(ctx.now, s),
    title: 'Calorías: ${ctx.kcalToday.round()} kcal',
    body: 'Faltan $missing kcal para la meta de ${ctx.kcalTarget}. El déficit es lo que frena la recomposición.',
  );
}

Iterable<PlannedNotification> _missingMeals(ReminderContext ctx) sync* {
  final s = ctx.setting(ReminderKind.comidasSinRegistrar);
  if (s == null || !s.enabled || ctx.missingMealsToday.isEmpty) return;
  final names = ctx.missingMealsToday.map((m) => m.label.toLowerCase()).toList();
  final list = names.length == 1 ? names.first : '${names.take(names.length - 1).join(', ')} y ${names.last}';
  yield PlannedNotification(
    kind: ReminderKind.comidasSinRegistrar,
    when: _at(ctx.now, s),
    title: '¿Cerraste el día? ${fmtInt(ctx.kcalToday)} kcal · ${fmtInt(ctx.proteinToday)} g',
    body: 'Falta registrar: $list. Si no comiste más hoy, ciérralo en Hoy o en Comidas para que cuente.',
  );
}

Iterable<PlannedNotification> _steps(ReminderContext ctx) sync* {
  final s = ctx.setting(ReminderKind.pasos);
  if (s == null || !s.enabled) return;
  // Solo entre semana: sábado y domingo son de fútbol y no tienen meta.
  if (stepsGoalFor(ctx.now, ctx.stepsTarget) == null) return;
  final threshold = s.threshold ?? 4000;
  final steps = ctx.stepsToday;
  if (steps != null && steps >= threshold) return;
  yield PlannedNotification(
    kind: ReminderKind.pasos,
    when: _at(ctx.now, s),
    title: steps == null ? 'Pasos: sin anotar hoy' : 'Pasos: ${fmtInt(steps)}',
    body: steps == null
        ? 'Mira el reloj y anótalos en Hoy. La meta es ${fmtInt(ctx.stepsTarget)}; una caminata de 20 min son ~2.000.'
        : 'Faltan ${fmtInt(ctx.stepsTarget - steps)} para ${fmtInt(ctx.stepsTarget)}. '
            'Una caminata de 20 min son ~2.000.',
  );
}

Iterable<PlannedNotification> _customReminders(ReminderContext ctx, ReminderDay day) sync* {
  for (final r in ctx.custom) {
    if (!r.dueOn(day.date)) continue;
    final overdue = day.date.isAfter(r.nextDue);
    yield PlannedNotification(
      kind: ReminderKind.personalizado,
      customId: r.id,
      when: DateTime(day.date.year, day.date.month, day.date.day, r.hour, r.minute),
      title: r.title,
      body: [
        if (r.note != null && r.note!.trim().isNotEmpty) r.note!.trim(),
        overdue
            ? 'Pendiente desde el ${weekdayShort(r.nextDue.weekday)} ${formatShort(r.nextDue)}. Márcalo en Hoy cuando lo hagas.'
            : 'Toca hoy (${r.frequencyLabel}). Márcalo como hecho en Hoy.',
      ].join('\n'),
    );
  }
}

Iterable<PlannedNotification> _measurement(ReminderContext ctx) sync* {
  final s = ctx.setting(ReminderKind.medicion);
  if (s == null || !s.enabled) return;

  final due = ctx.nextMeasurementDate ??
      (ctx.lastMeasurement == null ? null : addDays(ctx.lastMeasurement!, ctx.measureIntervalDays));
  if (due == null) return;

  // Si ya venció, recordarlo en la próxima mañana disponible.
  final day = due.isBefore(dateOnly(ctx.now)) ? addDays(dateOnly(ctx.now), 1) : due;
  final days = ctx.lastMeasurement == null ? null : daysBetween(ctx.lastMeasurement!, day);
  yield PlannedNotification(
    kind: ReminderKind.medicion,
    when: _at(day, s),
    title: 'Toca medir',
    body: days == null
        ? 'Tómate las medidas en ayunas, antes de desayunar.'
        : 'Han pasado $days días desde la última. En ayunas, antes de desayunar.',
  );
}

/// Resumen corto del día para el cuerpo de la notificación.
String planSummaryFor(DayType type, int? targetRounds, List<String> exerciseLabels) {
  if (type.isCircuit) {
    final rounds = targetRounds == null ? '' : ' $targetRounds rondas';
    return '${type.label}$rounds: ${exerciseLabels.join(' · ')}';
  }
  return '${type.label} — ${exerciseLabels.join(' · ')}';
}

/// Recordatorio que crea el usuario: "Ejercicios de cuello cada 3 días a las
/// 7:00 p. m.". Los días se cuentan desde la **última vez que se marcó como
/// hecho** (o desde el inicio, si nunca): así sirve para rutinas flexibles
/// ("cada 3–4 días") y un día saltado corre el siguiente. Mientras no se
/// marque, vuelve a avisar cada día a la misma hora.
class CustomReminder {
  const CustomReminder({
    required this.id,
    required this.title,
    this.note,
    required this.intervalDays,
    required this.hour,
    required this.minute,
    required this.startDate,
    this.lastDone,
    this.enabled = true,
  });

  final int id;
  final String title;
  final String? note;
  final int intervalDays;
  final int hour;
  final int minute;
  final DateTime startDate;
  final DateTime? lastDone;
  final bool enabled;

  /// Primer día en que toca.
  DateTime get nextDue => lastDone == null ? dateOnly(startDate) : addDays(dateOnly(lastDone!), intervalDays);

  /// Toca (o está pendiente) ese día: activo, ya llegó la fecha y no se hizo
  /// ese mismo día.
  bool dueOn(DateTime day) {
    final d = dateOnly(day);
    if (!enabled || d.isBefore(nextDue)) return false;
    return lastDone == null || d.isAfter(dateOnly(lastDone!));
  }

  /// "cada 3 días", "todos los días", "cada semana".
  String get frequencyLabel => switch (intervalDays) {
        1 => 'todos los días',
        7 => 'cada semana',
        final n => 'cada $n días',
      };

  String get timeLabel => timeKey(hour, minute);
}
