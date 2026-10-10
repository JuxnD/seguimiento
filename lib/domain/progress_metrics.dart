import 'dates.dart';
import 'fitness_test.dart';
import 'enums.dart';
import 'cindy_protocol.dart';
import 'session_math.dart';

enum RadarAxis {
  pull('Tirón', 'pullup', 'reps'),
  push('Empuje', 'pushup', 'reps'),
  core('Core', 'hollow_hold', 's'),
  legs('Piernas', 'bulgarian_split_squat', 'reps'),
  jump('Salto', 'broad_jump', 'cm'),
  circuit('Circuito', null, 'rondas');

  const RadarAxis(this.label, this.testId, this.unit);
  final String label, unit;
  final String? testId;
  String get protocol =>
      testId == null ? 'cindy20-5-10-15-bodyweight' : 'test:$testId';
}

class RadarReference {
  const RadarReference(
      {required this.id,
      required this.axis,
      required this.value,
      required this.unit,
      required this.from,
      this.until,
      required this.source,
      this.protocol});
  final String id, unit, source;
  final RadarAxis axis;
  final double value;
  final DateTime from;
  final DateTime? until;
  final String? protocol;
}

class RadarFreshnessPolicy {
  const RadarFreshnessPolicy({required this.maxAgeDays, required this.source});
  final int maxAgeDays;
  final String source;
}

class CindySet {
  const CindySet(
      {required this.exercise,
      required this.reps,
      this.variant,
      this.loadKg,
      this.split = false,
      this.toFailure = false});
  final String exercise;
  final int reps;
  final String? variant;
  final double? loadKg;
  final bool split, toFailure;
}

class CindyObservation {
  CindyObservation(
      {required this.id,
      required this.date,
      required this.type,
      required this.mode,
      required this.totalSec,
      required this.warmupSec,
      required this.cooldownSec,
      required this.rounds,
      required this.extraReps,
      required List<CindySet> sets,
      required this.imported,
      required this.estimated,
      required this.incomplete,
      this.techniqueOk,
      this.fullRange})
      : sets = List.unmodifiable(sets);
  final String id;
  final DateTime? date;
  final SessionType type;
  final String? mode;
  final int totalSec, warmupSec, cooldownSec;
  final int? rounds, extraReps;
  final List<CindySet> sets;
  final bool imported, estimated, incomplete;
  final bool? techniqueOk, fullRange;
}

class RadarObservation {
  RadarObservation(
      {required this.sourceKey,
      required this.protocol,
      required this.value,
      required this.date,
      required this.orderDate,
      required this.eligible,
      required this.reason,
      required this.quality,
      required this.raw,
      List<TestResult> testRows = const [],
      this.cindy})
      : testRows = List.unmodifiable(testRows);
  final String sourceKey, protocol, reason, quality, raw;
  final double? value;
  final DateTime? date, orderDate;
  final bool eligible;
  final List<TestResult> testRows;
  final CindyObservation? cindy;
}

class RadarAxisEvidence {
  RadarAxisEvidence(
      {required this.axis,
      this.firstEligible,
      this.lastEligible,
      this.current,
      this.latestObserved,
      List<RadarObservation> observations = const [],
      this.reference,
      this.referenceIssue = '',
      this.currentIssue = ''})
      : observations = List.unmodifiable(observations);
  final RadarAxis axis;
  final RadarObservation? firstEligible, lastEligible, current, latestObserved;
  final List<RadarObservation> observations;
  final RadarReference? reference;
  final String referenceIssue, currentIssue;
  double? get initialPercent => _percent(firstEligible?.value);
  double? get currentPercent => _percent(current?.value);
  double? _percent(double? value) {
    if (value == null || reference == null) return null;
    final pct = value / reference!.value * 100;
    return pct.isFinite ? pct : null;
  }

  bool get hasDifferentDates =>
      firstEligible?.date != null &&
      current?.date != null &&
      dayKey(firstEligible!.date!) != dayKey(current!.date!);
  double? get changePercent => hasDifferentDates
      ? improvement(firstEligible?.value, current?.value)
      : null;
}

class PersonalRadar {
  PersonalRadar(
      {required this.asOf,
      required List<RadarAxisEvidence> axes,
      this.freshness})
      : axes = List.unmodifiable(axes);
  final DateTime asOf;
  final List<RadarAxisEvidence> axes;
  final RadarFreshnessPolicy? freshness;
  RadarAxisEvidence axis(RadarAxis a) => axes.singleWhere((e) => e.axis == a);
  bool get hasRecords => axes.any((a) => a.observations.isNotEmpty);
}

PersonalRadar buildPersonalRadar(
    {required List<TestResult> tests,
    List<CindyObservation> cindy = const [],
    Map<RadarAxis, RadarReference> references = const {},
    required DateTime asOf,
    RadarFreshnessPolicy? freshness}) {
  final cutoff = dateOnly(asOf);
  if (freshness != null &&
      (freshness.maxAgeDays < 0 || freshness.source.trim().isEmpty)) {
    throw ArgumentError(
        'La ventana de actualidad requiere días válidos y fuente.');
  }
  final axes = <RadarAxisEvidence>[];
  for (final axis in RadarAxis.values) {
    final observations = axis.testId == null
        ? [for (final row in cindy) _cindyEvidence(row, cutoff)]
        : _testEvidence(axis, tests, cutoff);
    observations.sort((a, b) {
      if (a.orderDate == null && b.orderDate != null) return -1;
      if (b.orderDate == null && a.orderDate != null) return 1;
      final byDate = a.orderDate?.compareTo(b.orderDate!) ?? 0;
      return byDate == 0 ? a.sourceKey.compareTo(b.sourceKey) : byDate;
    });
    final eligible = observations.where((o) => o.eligible).toList();
    RadarObservation? last = eligible.lastOrNull;
    if (axis.testId != null) {
      final round = latestEligibleTestRound(tests, axis.testId!, asOf: cutoff);
      final shared =
          eligible.where((o) => o.testRows.first.round == round).firstOrNull;
      if (shared != null) last = shared;
    }
    final old = last != null &&
        freshness != null &&
        daysBetween(last.date!, cutoff) > freshness.maxAgeDays;
    final ref = references[axis];
    final refIssue = _referenceError(ref, axis, cutoff);
    axes.add(RadarAxisEvidence(
        axis: axis,
        firstEligible: eligible.firstOrNull,
        lastEligible: last,
        current: old ? null : last,
        latestObserved:
            observations.where((o) => o.orderDate != null).lastOrNull,
        observations: observations,
        reference: refIssue.isEmpty ? ref : null,
        referenceIssue: refIssue,
        currentIssue: old
            ? 'Fuera de la ventana de ${freshness.maxAgeDays} días: ${freshness.source}. La medición histórica se conserva.'
            : last == null
                ? 'Sin prueba apta hasta la fecha de corte.'
                : ''));
  }
  return PersonalRadar(asOf: cutoff, axes: axes, freshness: freshness);
}

String _referenceError(RadarReference? ref, RadarAxis axis, DateTime cutoff) {
  if (ref == null) return 'Sin referencia personal.';
  if (ref.axis != axis || ref.unit != axis.unit) {
    return 'Referencia de otro eje o unidad.';
  }
  if (!ref.value.isFinite || ref.value <= 0) {
    return 'Referencia no positiva o no finita.';
  }
  if (ref.id.trim().isEmpty || ref.source.trim().isEmpty) {
    return 'Referencia sin identidad o fuente.';
  }
  if (dateOnly(ref.from).isAfter(cutoff) ||
      (ref.until != null && dateOnly(ref.until!).isBefore(cutoff))) {
    return 'Referencia fuera de vigencia.';
  }
  if (ref.protocol != null && ref.protocol != axis.protocol) {
    return 'Referencia de otro protocolo.';
  }
  return '';
}

List<RadarObservation> _testEvidence(
    RadarAxis axis, List<TestResult> tests, DateTime cutoff) {
  final item = testItem(axis.testId!)!;
  final rounds =
      tests.where((r) => r.item == item.id).map((r) => r.round).toSet();
  return [
    for (final round in rounds)
      () {
        final rows =
            tests.where((r) => r.item == item.id && r.round == round).toList();
        final dates = rows
            .where((r) => r.date != null)
            .map((r) => dayKey(r.date!))
            .toSet();
        final date = dates.length == 1 && rows.every((r) => r.date != null)
            ? dateOnly(rows.first.date!)
            : null;
        final dated = rows
            .where((r) => r.date != null)
            .map((r) => dateOnly(r.date!))
            .toList()
          ..sort();
        final structurallyValid = round >= 1 &&
            round <= 3 &&
            rows.length == (item.perSide ? 2 : 1) &&
            rows.every((r) => testResultError(item, r.value) == null) &&
            (item.perSide
                ? rows.map((r) => r.side).toSet().containsAll(['I', 'D'])
                : rows.single.side == null);
        final value = testValue(tests, round, item.id);
        final apt = structurallyValid &&
            eligibleTestValue(tests, round, item.id, asOf: cutoff) != null;
        final reasons = [
          if (!structurallyValid || value == null)
            'Parcial, valor/lado inválido o filas duplicadas',
          if (rows.any((r) => !r.clean)) 'Técnica declarada con dudas',
          if (rows.any((r) => r.date == null)) 'Fecha sin registrar',
          if (dates.length > 1) 'Fechas distintas en el mismo intento',
          if (dated.any((d) => d.isAfter(cutoff)))
            'Fecha futura respecto del corte'
        ];
        return RadarObservation(
            sourceKey: 'test:${item.id}:T$round',
            protocol: axis.protocol,
            value: structurallyValid ? value : null,
            date: date,
            orderDate: dated.lastOrNull,
            eligible: apt,
            reason: reasons.join('. '),
            quality: rows.every((r) => r.clean)
                ? 'Técnica declarada limpia'
                : 'Técnica declarada con dudas',
            testRows: rows,
            raw:
                'T$round · ${item.name}: ${rows.map((r) => '${r.side == null ? '' : '${r.side}: '}${r.value} ${item.unit.short} · ${r.date == null ? 'fecha sin registrar' : dayKey(r.date!)}${r.clean ? '' : ' · con dudas'}').join('; ')}');
      }()
  ];
}

RadarObservation _cindyEvidence(CindyObservation row, DateTime cutoff) {
  final span = circuitSpanSec(
      totalSec: row.totalSec,
      warmupSec: row.warmupSec,
      cooldownSec: row.cooldownSec);
  final counts = row.rounds != null &&
      row.rounds! >= 0 &&
      row.extraReps != null &&
      row.extraReps! >= 0 &&
      row.extraReps! < cindyRepsPerRound;
  // Structural bound before multiplication prevents integer overflow without
  // imposing an invented maximum number of physically possible rounds.
  var recipe = counts &&
      row.sets.isNotEmpty &&
      row.rounds! > 0 &&
      row.rounds! <= row.sets.length ~/ cindyRound.length;
  final fullSetCount = recipe ? row.rounds! * cindyRound.length : 0;
  final partial =
      counts ? splitPartialRound(row.extraReps!) : <(String, int)>[];
  recipe = recipe && row.sets.length == fullSetCount + partial.length;
  if (recipe) {
    for (var i = 0; i < row.sets.length; i++) {
      final expected = i < fullSetCount
          ? cindyRound[i % cindyRound.length]
          : partial[i - fullSetCount];
      final set = row.sets[i];
      if (set.exercise != expected.$1 ||
          set.reps != expected.$2 ||
          set.variant != null ||
          set.loadKg != null ||
          set.split ||
          set.toFailure) {
        recipe = false;
        break;
      }
    }
  }
  final dates = row.date == null ? null : dateOnly(row.date!);
  final reasons = [
    if (dates == null) 'Fecha sin registrar',
    if (dates != null && dates.isAfter(cutoff))
      'Fecha futura respecto del corte',
    if (row.type != SessionType.resistencia || row.mode != 'cindy')
      'Otro tipo o formato de sesión',
    if (row.totalSec < 0 ||
        row.warmupSec < 0 ||
        row.cooldownSec < 0 ||
        span != 1200)
      'Ventana real distinta de20min',
    if (!counts) 'Conteo o reps parciales inválidos/desconocidos',
    if (!recipe)
      'Receta, variante o lastre no demuestran Cindy5/10/15 sin peso externo',
    if (row.imported) 'Historial importado',
    if (row.estimated) 'Conteo estimado',
    if (row.incomplete) 'Sesión cortada',
    if (row.techniqueOk == false || row.fullRange == false)
      'Técnica o rango declarados con dudas'
  ];
  final value = counts && recipe
      ? row.rounds! + row.extraReps! / cindyRepsPerRound
      : null;
  return RadarObservation(
      sourceKey: 'session:${row.id}',
      protocol: RadarAxis.circuit.protocol,
      value: value,
      date: dates,
      orderDate: dates,
      eligible: reasons.isEmpty,
      reason: reasons.join('. '),
      quality: row.techniqueOk == true && row.fullRange == true
          ? 'Técnica/rango declarados positivos'
          : row.techniqueOk == false || row.fullRange == false
              ? 'Técnica/rango con dudas'
              : 'Técnica/rango no declarados; aptitud del conteo y receta, no certificación técnica',
      cindy: row,
      raw:
          '${row.rounds ?? '?'} rondas + ${row.extraReps ?? '?'} reps · ventana $span s · '
          '${row.sets.map((s) => '${s.exercise}:${s.reps}, variante ${s.variant ?? 'sin variante'}, lastre ${s.loadKg ?? 'sin peso externo'}${s.split ? ', partida' : ''}${s.toFailure ? ', fallo' : ''}').join('; ')}');
}
