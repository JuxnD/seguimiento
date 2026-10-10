import 'package:drift/drift.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/nutrition.dart';
import '../../domain/progress.dart';
import '../../domain/progress_evidence.dart';
import '../../domain/chart_evidence.dart';
import '../../domain/session_math.dart';
import '../../domain/format.dart';
import '../../domain/recovery.dart';
import '../database.dart';
import 'nutrition_repository.dart';
import 'training_repository.dart';

/// Date-aware read model, no history writes or inferred goals.
class ChartRepository {
  ChartRepository(this.db, this.nutrition);
  final AppDatabase db;
  final NutritionRepository nutrition;
  Future<List<SeriesPoint>> rounds(
      {DateTime? from,
      DateTime? to,
      int limit = 200,
      SessionType? only}) async {
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.roundsDone.isNotNull() &
              (only == null
                  ? t.type.isIn([
                      ...SessionType.values
                          .where((t) => t.isCircuit)
                          .map((t) => t.name),
                      SessionType.resistencia.name
                    ])
                  : t.type.equalsValue(only)) &
              (from == null
                  ? const Constant(true)
                  : t.date.isBiggerOrEqualValue(dayKey(from))) &
              (to == null
                  ? const Constant(true)
                  : t.date.isSmallerOrEqualValue(dayKey(to))))
          ..orderBy([
            (t) => OrderingTerm.desc(t.date),
            (t) => OrderingTerm.desc(t.id)
          ])
          ..limit(limit.clamp(1, 200)))
        .get();
    if (rows.isEmpty) return [];
    final ids = rows.map((s) => s.id).toList();
    // Bounded batch queries, not load(sessionId) inside a loop.
    final sets = await (db.select(db.sessionSets).join([
      innerJoin(
          db.exercises, db.exercises.id.equalsExp(db.sessionSets.exerciseId))
    ])
          ..where(db.sessionSets.sessionId.isIn(ids)))
        .get();
    final recorded = <int, List<SetDraft>>{};
    for (final r in sets) {
      final s = r.readTable(db.sessionSets);
      recorded.putIfAbsent(s.sessionId, () => []).add(SetDraft(
          exercise: r.readTable(db.exercises).name,
          reps: s.reps,
          variant: s.variant,
          loadKg: s.loadKg));
    }
    final laps = await (db.select(db.sessionRounds)
          ..where((t) => t.sessionId.isIn(ids))
          ..orderBy([(t) => OrderingTerm.asc(t.roundIndex)]))
        .get();
    final marks = <int, List<SessionRoundRow>>{};
    for (final r in laps) {
      marks.putIfAbsent(r.sessionId, () => []).add(r);
    }
    return [
      for (final s in rows.reversed)
        () {
          final dose =
              SessionDraft(date: parseDay(s.date), sets: recorded[s.id])
                  .exerciseProtocol;
          final r = marks[s.id] ?? [];
          final work = r.isNotEmpty && r.every((r) => r.workSec != null);
          final span = circuitSpanSec(
              totalSec: s.totalSec,
              warmupSec: s.warmupSec,
              cooldownSec: s.cooldownSec);
          final timedWindow = s.type == SessionType.resistencia ? span : null;
          final cut = s.mode == 'cindy' && span < 1200;
          final evidence = RoundTimingEvidence(
              sessionId: s.id,
              date: parseDay(s.date),
              type: s.type,
              mode: s.mode,
              planDayId: s.planDayId,
              exerciseProtocol: dose,
              basis: work ? TimingBasis.work : TimingBasis.lap,
              durationsSec: const [],
              imported: s.imported,
              estimated: s.roundsEstimated,
              incomplete: s.incomplete || cut);
          final eligible =
              evidence.comparableTo(evidence) && s.mode != 'tecnica';
          final reasons = [
            if (s.imported) 'historial importado',
            if (s.roundsEstimated) 'rondas estimadas',
            if (s.incomplete) 'sesión cortada',
            if (cut) 'Cindy menor de20min: no es marca de20min',
            if (s.mode == 'tecnica') 'práctica de técnica',
            if (s.planDayId == null) 'plan no registrado',
            if (dose == null) 'ejercicios/dosis no registrados'
          ];
          final mode = s.mode ?? 'normal',
              label = '${s.type.label} · ${s.mode ?? 'normal'}';
          final doseLabel = (recorded[s.id] ?? [])
              .map((s) =>
                  '${s.exercise} ${s.reps} reps · ${s.variant ?? "variante no anotada"} · ${s.loadKg == null ? "peso corporal" : "${fmtDec(s.loadKg!)} kg"}')
              .toSet()
              .join('; ');
          return SeriesPoint(parseDay(s.date), s.roundsDone!.toDouble(),
              label: label,
              protocolLabel:
                  '$label · plan ${s.planDayId ?? "no identificado"}\n${doseLabel.isEmpty ? "Dosis no registrada" : doseLabel}${timedWindow == null ? "" : "\nVentana ${holdLabel(timedWindow, null)}"}\n${work ? "Trabajo separado del descanso" : "Tiempo por ronda sin desglose de trabajo"}',
              protocol:
                  '${s.type.name}|$mode|${s.planDayId}|$dose|${evidence.basis.name}|${timedWindow ?? "sin ventana fija"}',
              comparable: eligible,
              sourceId: s.id,
              evidence:
                  '$label · sesión ${s.id} · plan ${s.planDayId ?? "sin identificar"}\n${timedWindow == null ? "" : "Ventana de circuito registrada: $timedWindow s.\n"}${recorded[s.id]?.map((s) => "${s.exercise}: ${s.reps} reps · ${s.variant ?? "sin variante anotada"} · ${s.loadKg == null ? "sin lastre anotado" : "${s.loadKg} kg"}").join("\n") ?? "Sin dosis registrada"}\n${eligible ? "Mismo protocolo registrado; comparación descriptiva de rondas." : "Observación: ${reasons.join(", ")}; no prueba mejora comparable."}');
        }()
    ];
  }

  Future<List<ChartDay>> nutritionDays(DateTime from, DateTime to,
      {bool protein = true}) async {
    final meals = await nutrition.range(from, to);
    final closed = await (db.select(db.closedDays)
          ..where((t) => t.date.isBetweenValues(dayKey(from), dayKey(to))))
        .get();
    final closures = closed.map((d) => d.date).toSet(),
        byDay = <String, List<MealWithItems>>{};
    for (final m in meals) {
      byDay.putIfAbsent(m.meal.date, () => []).add(m);
    }
    return [
      for (var d = dateOnly(from); !d.isAfter(dateOnly(to)); d = addDays(d, 1))
        () {
          final found = byDay[dayKey(d)];
          if (found == null) return ChartDay(d, null, ChartDayStatus.missing);
          final macros = Macros.sum(found.map((m) => m.macros));
          final done = isDayClosed(found.map((m) => m.meal.slot).toSet(),
              manuallyClosed: closures.contains(dayKey(d)),
              mealCount: found.length,
              kcal: macros.kcal);
          final estimated = found
              .expand((m) => m.items)
              .where((i) => i.sourceVerified == null)
              .length;
          return ChartDay(d, protein ? macros.protein : macros.kcal,
              done ? ChartDayStatus.closed : ChartDayStatus.incomplete,
              evidence:
                  '${found.length} comidas · $estimated ítems estimados. Misma regla de cierre del informe; no valida cifras nutricionales.');
        }()
    ];
  }

  /// Old adapter retains observed zeros, excludes absence. Core fillDays intact.
  Future<List<SeriesPoint>> nutritionDaily(DateTime from, DateTime to,
          {bool protein = true}) async =>
      [
        for (final d in await nutritionDays(from, to, protein: protein))
          if (d.value != null)
            SeriesPoint(d.date, d.value!,
                label: d.statusLabel, evidence: d.evidence)
      ];
  Future<List<SeriesPoint>> measurements(MeasureSite site,
      {LengthUnit unit = LengthUnit.cm, DateTime? from, DateTime? to}) async {
    final rows = await (db.select(db.measurements)
          ..where((t) =>
              t.site.equalsValue(site) &
              (from == null
                  ? const Constant(true)
                  : t.date.isBiggerOrEqualValue(dayKey(from))) &
              (to == null
                  ? const Constant(true)
                  : t.date.isSmallerOrEqualValue(dayKey(to))))
          ..orderBy(
              [(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)]))
        .get();
    return [
      for (final m in rows)
        SeriesPoint(parseDay(m.date), fromCm(m.valueCm, unit),
            label: site.label,
            protocol: '${site.name}|${unit.name}|${m.fasted}',
            protocolLabel:
                '${site.label} · ${unit.label} · ${m.fasted ? "En ayunas (indicador guardado)" : "Fuera de ayunas: referencia"}',
            comparable: m.fasted,
            sourceId: m.id,
            evidence:
                '${site.label} · ${m.valueCm} cm en SQLite · unidad ${unit.label}. Ayuno: ${m.fasted ? "sí, según indicador guardado" : "no"}. Hora: ${m.time ?? "no anotada"}. Técnica de medición sin registrar; ${m.fasted ? "diferencia descriptiva, sin consejo" : "referencia, sin evolución comparable"}.')
    ];
  }

  Future<List<SeriesPoint>> weights({DateTime? from, DateTime? to}) async {
    final rows = await (db.select(db.bodyWeights)
          ..where((t) =>
              (from == null
                  ? const Constant(true)
                  : t.date.isBiggerOrEqualValue(dayKey(from))) &
              (to == null
                  ? const Constant(true)
                  : t.date.isSmallerOrEqualValue(dayKey(to))))
          ..orderBy(
              [(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)]))
        .get();
    return [
      for (final w in rows)
        () {
          final recognized = w.moment == null ||
              WeighMoment.values.any((m) => m.name == w.moment);
          final moment = weighMomentOf(w.moment, fasted: w.fasted);
          final label = !recognized
              ? 'Momento no reconocido'
              : w.moment == null
                  ? w.fasted
                      ? 'En ayunas (indicador guardado)'
                      : 'Fuera de ayunas · momento no anotado'
                  : moment.label;
          final comparable = recognized && moment == WeighMoment.ayunas;
          final key = !recognized
              ? 'momento desconocido'
              : w.moment == null && !w.fasted
                  ? 'momento no anotado'
                  : moment.name;
          return SeriesPoint(parseDay(w.date), w.kg,
              label: label,
              protocol: key,
              protocolLabel: '$label · kg',
              comparable: comparable,
              sourceId: w.id,
              evidence:
                  '$label · kg. Momento guardado: ${w.moment ?? "no anotado; fallback compartido desde indicador ayuno"}. Ayuno guardado: ${w.fasted}. Hora: ${w.time ?? "no anotada"}. ${comparable ? "Comparación descriptiva con condición de ayuno guardada." : "Referencia visible; no prueba evolución comparable."}');
        }()
    ];
  }

  Future<List<MeasureSite>> sitesWithHistory(
      {DateTime? from, DateTime? to}) async {
    final q = db.selectOnly(db.measurements, distinct: true)
      ..addColumns([db.measurements.site]);
    q.where((from == null
            ? const Constant(true)
            : db.measurements.date.isBiggerOrEqualValue(dayKey(from))) &
        (to == null
            ? const Constant(true)
            : db.measurements.date.isSmallerOrEqualValue(dayKey(to))));
    q.orderBy([OrderingTerm.asc(db.measurements.site)]);
    return q
        .map((r) => MeasureSite.values.byName(r.read(db.measurements.site)!))
        .get();
  }
}
