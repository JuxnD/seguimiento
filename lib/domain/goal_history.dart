import 'dates.dart';
import 'nutrition.dart' show dailyKcalTarget;

// Metas con historia (plan 009, ADR 0016): cada día se evalúa con la meta
// vigente ese día. Una meta nueva no reclasifica el pasado. Lo anterior a la
// primera vigencia conocida es "meta histórica no registrada": no se inventa
// cuándo cambió.

enum GoalMetric {
  pasos('Pasos diarios entre semana', 'pasos'),
  proteinaMin('Proteína mínima', 'g'),
  proteinaMax('Proteína máxima', 'g'),
  kcal('kcal entre semana', 'kcal'),
  kcalFutbol('kcal en días de fútbol', 'kcal'),

  /// Piso de alerta de kcal (plan 022): opcional, misma historia. null
  /// conocido = se decidió no tener piso.
  kcalFloor('Piso de kcal', 'kcal'),

  // Referencias del radar (plan 011): opcionales, sin valor por defecto ni
  // proyección al perfil. null = sin referencia. Sólo con aceptación explícita.
  refDominadas('Dominadas estrictas', 'reps', reference: true),
  refFlexiones('Flexiones', 'reps', reference: true),
  refHollow('Hollow hold', 's', reference: true),
  refBulgara('Búlgara por lado', 'reps', reference: true),
  refSaltoLargo('Salto largo', 'cm', reference: true),
  refCindy('Cindy 20 min', 'rondas', reference: true);

  const GoalMetric(this.label, this.unit, {this.reference = false});
  final String label;
  final String unit;

  /// Referencia del radar: no es meta diaria ni vive en el perfil.
  final bool reference;
}

/// Origen de una vigencia.
abstract final class GoalOrigin {
  /// Copiada del perfil al migrar: no se sabe desde cuándo regía.
  static const legado = 'legado';

  /// Meta inicial de una instalación nueva.
  static const inicio = 'inicio';

  /// Editada en Ajustes.
  static const perfil = 'perfil';

  /// Aceptada desde una propuesta del acompañamiento.
  static const propuesta = 'propuesta';

  /// Puesta por un plan o una corrección del traspaso.
  static const plan = 'plan';
}

class GoalVersion {
  const GoalVersion({
    this.id,
    required this.metric,
    required this.value,
    required this.effectiveFrom,
    required this.acceptedAt,
    required this.origin,
    this.reason,
    this.policy = 1,
  });

  final int? id;
  final GoalMetric metric;

  /// null = sin meta (p. ej. kcal de fútbol igual a la de entre semana).
  final double? value;

  /// null sólo en lo legado: rige desde una fecha que no se registró.
  final DateTime? effectiveFrom;
  final DateTime acceptedAt;
  final String origin;
  final String? reason;
  final int policy;

  bool get legacy => effectiveFrom == null;
}

/// La meta de un día y si se sabe que regía ese día.
class GoalAt {
  const GoalAt(this.value, {required this.known, this.since});

  final double? value;

  /// false: el día es anterior a toda vigencia registrada (meta histórica
  /// no registrada). El valor es el legado, sólo como referencia.
  final bool known;
  final DateTime? since;

  /// Sólo una referencia conocida positiva permite comparar lo registrado.
  bool get comparable =>
      known && value != null && value!.isFinite && value! > 0;

  String get absenceLabel => known ? 'Sin meta' : 'Meta no registrada';
}

/// null en la historia es compatibilidad legacy explícita; una historia
/// cargada incompleta nunca usa la proyección interna del perfil.
GoalAt goalReferenceOn(GoalHistory? history, GoalMetric metric, DateTime day,
        {num? fallback}) =>
    history == null
        ? GoalAt(fallback?.toDouble(), known: true)
        : history.on(metric, day) ?? const GoalAt(null, known: false);

/// Conserva el calendario existente, sin inferir metas desde partidos.
GoalAt kcalGoalReferenceOn(GoalHistory? history, DateTime day,
    {num? weekdayFallback, num? footballFallback}) {
  final weekly =
      goalReferenceOn(history, GoalMetric.kcal, day, fallback: weekdayFallback);
  if (dailyKcalTarget(day: day, weekdayTarget: 0, footballTarget: 1) == 0)
  {
    return weekly;
  }
  final football = goalReferenceOn(history, GoalMetric.kcalFutbol, day,
      fallback: footballFallback);
  if (!football.known) return football;
  return football.value == null ? weekly : football;
}

class GoalHistory {
  GoalHistory(Iterable<GoalVersion> versions) : _versions = [...versions]..sort(_order);

  final List<GoalVersion> _versions;

  List<GoalVersion> get versions => List.unmodifiable(_versions);

  static int _order(GoalVersion a, GoalVersion b) {
    final fa = a.effectiveFrom, fb = b.effectiveFrom;
    if (fa == null && fb != null) return -1;
    if (fb == null && fa != null) return 1;
    final c = fa == null ? 0 : dateOnly(fa).compareTo(dateOnly(fb!));
    if (c != 0) return c;
    // Mismo día: gana la última registrada.
    return (a.id ?? 0).compareTo(b.id ?? 0);
  }

  Iterable<GoalVersion> of(GoalMetric m) => _versions.where((v) => v.metric == m);

  GoalAt? on(GoalMetric m, DateTime day) {
    final d = dateOnly(day);
    GoalVersion? legacy;
    GoalVersion? known;
    for (final v in of(m)) {
      if (v.legacy) {
        legacy = v;
      } else if (!dateOnly(v.effectiveFrom!).isAfter(d)) {
        known = v;
      }
    }
    if (known != null) return GoalAt(known.value, known: true, since: known.effectiveFrom);
    if (legacy != null) return GoalAt(legacy.value, known: false);
    return null;
  }

  /// La vigencia actual (la última conocida o, si no hay, la legada).
  GoalVersion? current(GoalMetric m, DateTime today) {
    final d = dateOnly(today);
    GoalVersion? out;
    for (final v in of(m)) {
      if (v.legacy || !dateOnly(v.effectiveFrom!).isAfter(d)) out = v;
    }
    return out;
  }

  /// La vigencia anterior a la actual, para poder volver.
  GoalVersion? previous(GoalMetric m, DateTime today) {
    final all = [
      for (final v in of(m))
        if (v.legacy || !dateOnly(v.effectiveFrom!).isAfter(dateOnly(today))) v,
    ];
    return all.length < 2 ? null : all[all.length - 2];
  }
}

/// Las metas que rigieron en unos días (plan 009, R2): un informe de un
/// período pasado imprime la meta de ese período, el cambio si lo hubo o la
/// incertidumbre, nunca la actual sobre días que tenían otra.
class GoalSpan {
  const GoalSpan(this.segments, {this.unknownDays = 0});

  /// Sin historia cargada: la meta de siempre en todos los días.
  factory GoalSpan.over(GoalHistory? goals, GoalMetric m, Iterable<DateTime> days, {num? fallback}) {
    return GoalSpan.fromReferences(
        days, (day) => goalReferenceOn(goals, m, day, fallback: fallback));
  }

  /// La misma compresión de referencias para texto, alertas y gráficas011.
  factory GoalSpan.fromReferences(
      Iterable<DateTime> days, GoalAt Function(DateTime) resolve) {
    final sorted = [for (final d in days) dateOnly(d)]..sort();
    final segments = <({double? value, DateTime from})>[];
    var unknown = 0;
    for (final d in sorted) {
      final at = resolve(d);
      if (!at.known) {
          unknown++;
          continue;
        }
      final value = at.value;
      if (segments.isEmpty || segments.last.value != value) segments.add((value: value, from: d));
    }
    return GoalSpan(segments, unknownDays: unknown);
  }

  /// Cada vigencia conocida, con el primer día del período en que rigió.
  final List<({double? value, DateTime from})> segments;

  /// Días anteriores a toda vigencia registrada: no se comparan.
  final int unknownDays;

  bool get changed => segments.length > 1;

  /// La única meta del período; null si cambió, si una parte no se sabe o si
  /// es "sin meta".
  double? get single => segments.length == 1 && unknownDays == 0 ? segments.first.value : null;

  /// Para un rótulo corto: "130→160", "?" lo que no se sabe.
  String short(String Function(double v) fmt) => [
        if (unknownDays > 0) '?',
        for (final x in segments) x.value == null ? '—' : fmt(x.value!),
      ].join('→');

  /// "130", "130 → 160 desde el 15 oct", "histórica no registrada"…
  String label(String Function(double v) fmt, {String none = 'sin meta'}) {
    if (segments.isEmpty) return 'histórica no registrada';
    final b = StringBuffer();
    for (var i = 0; i < segments.length; i++) {
      final v = segments[i].value;
      if (i > 0) b.write(' → ');
      b.write(v == null ? none : fmt(v));
      if (i > 0) b.write(' desde el ${formatShort(segments[i].from)}');
    }
    if (unknownDays > 0) {
      b.write('; $unknownDays ${unknownDays == 1 ? 'día' : 'días'} con meta histórica no registrada');
    }
    return b.toString();
  }
}
