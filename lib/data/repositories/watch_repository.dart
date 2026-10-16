import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/watch_capture.dart';
import '../database.dart';

/// Plan 058 (§16.17): lo que se trae del reloj INNOVA por captura o a mano.
class WatchRepository {
  WatchRepository(this.db);
  final AppDatabase db;

  /// Guarda la actividad (y, si la captura traía presión o SpO₂, el signo).
  /// Rechaza lo que cae fuera de rango; no inventa campos vacíos.
  Future<int?> saveReading(WatchReading r,
      {required DateTime date,
      int? sessionId,
      required String source,
      DateTime? now}) async {
    final problem = watchReadingProblem(r);
    if (problem != null) throw FormatException(problem);
    return db.transaction(() async {
      int? id;
      if (r.hasActivity) {
        id = await db.into(db.watchActivities).insert(
            WatchActivitiesCompanion.insert(
              sessionId: Value(sessionId),
              date: dayKey(dateOnly(date)),
              startTime: Value(r.startTime),
              kind: Value(r.kind),
              durationSec: Value(r.durationSec),
              avgHr: Value(r.avgHr),
              maxHr: Value(r.maxHr),
              kcal: Value(r.kcal),
              steps: Value(r.steps),
              distanceM: Value(r.distanceM),
              source: source,
              createdAt: (now ?? DateTime.now()).toIso8601String(),
            ));
      }
      if (r.hasVitals) {
        await saveVital(
            date: date,
            time: r.startTime,
            systolic: r.systolic,
            diastolic: r.diastolic,
            spo2: r.spo2,
            source: 'reloj');
      }
      return id;
    });
  }

  Future<int> saveVital(
      {required DateTime date,
      String? time,
      int? systolic,
      int? diastolic,
      int? spo2,
      bool atRest = true,
      required String source,
      String? note}) {
    final problem = watchReadingProblem(
        WatchReading(systolic: systolic, diastolic: diastolic, spo2: spo2));
    if (problem != null) throw FormatException(problem);
    if (systolic == null && spo2 == null) {
      throw const FormatException('Falta la presión o la SpO₂');
    }
    return db.into(db.watchVitals).insert(WatchVitalsCompanion.insert(
          date: dayKey(dateOnly(date)),
          time: Value(time),
          systolic: Value(systolic),
          diastolic: Value(diastolic),
          spo2: Value(spo2),
          atRest: Value(atRest),
          source: source,
          note: Value(note),
        ));
  }

  Future<List<WatchActivityRow>> forSession(int sessionId) =>
      (db.select(db.watchActivities)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();

  Stream<List<WatchActivityRow>> watchForSession(int sessionId) =>
      (db.select(db.watchActivities)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .watch();

  Future<void> deleteActivity(int id) =>
      (db.delete(db.watchActivities)..where((t) => t.id.equals(id))).go();

  /// Las lecturas para la tendencia: en reposo, de la más reciente hacia
  /// atrás. Las del tensiómetro van marcadas y tienen prioridad al leerlas.
  Stream<List<WatchVitalRow>> watchVitals({int limit = 30}) =>
      (db.select(db.watchVitals)
            ..orderBy([
              (t) => OrderingTerm.desc(t.date),
              (t) => OrderingTerm.desc(t.id)
            ])
            ..limit(limit))
          .watch();

  Future<void> deleteVital(int id) =>
      (db.delete(db.watchVitals)..where((t) => t.id.equals(id))).go();
}
