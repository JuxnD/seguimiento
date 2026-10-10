import 'dates.dart';

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
