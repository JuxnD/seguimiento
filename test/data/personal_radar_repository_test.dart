import 'dart:io';
import 'package:drift/native.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/personal_radar_repository.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/domain/progress_metrics.dart';
import '../support/sqlite_host.dart';
import '../support/radar_fixture.dart';
import '../support/radar_sql_fixture.dart';

class _Today extends TodayNotifier {
  @override
  DateTime build() => radarDay;
}

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late GoalRepository goals;
  late PersonalRadarRepository repo;
  setUp(() {
    db = openInMemoryDatabase();
    goals = GoalRepository(db);
    repo = PersonalRadarRepository(db);
  });
  tearDown(() => db.close());
  Future<PersonalRadar> read({DateTime? end}) async =>
      repo.load(end: end ?? radarDay, today: radarDay, history: await goals.history());

  test('SQLite completo, corte y referencia común desde vigencia real', () async {
    await seedRadarSql(db);
    final all = await read();
    expect(all.axes.every((e) => e.current != null && e.reference != null), isTrue);
    expect(all.axis(RadarAxis.legs).current!.value, 20);
    expect(all.axis(RadarAxis.circuit).current!.value, 8.5);
    final past = await read(end: DateTime(2026, 10, 2));
    expect(past.axis(RadarAxis.pull).current!.value, 5);
    expect(past.axis(RadarAxis.circuit).current!.value, 6.5);
    expect(past.axis(RadarAxis.pull).changePercent, isNull);
    await goals.setReference(GoalMetric.refDominadas, 20, now: radarDay);
    final changed = (await read()).axis(RadarAxis.pull);
    expect((changed.initialPercent, changed.currentPercent), (25, 40));
    expect((await read(end: DateTime(2026, 10, 9))).axis(RadarAxis.pull).currentPercent, 80);
    await goals.setReference(GoalMetric.refDominadas, null, now: radarDay);
    expect((await read()).axis(RadarAxis.pull).currentPercent, isNull);
    expect((await read()).axis(RadarAxis.pull).current!.value, 8);
  });
  test('bilateral parcial, futuro e inválido no ocultan apta anterior', () async {
    await seedRadarSql(db);
    await db.into(db.fitnessTests).insert(FitnessTestsCompanion.insert(
        round: 3, item: 'bulgarian_split_squat', value: 99, date: '2026-10-10', side: const Value('I')));
    await db
        .into(db.fitnessTests)
        .insert(FitnessTestsCompanion.insert(round: 3, item: 'pullup', value: 25, date: '2026-10-11'));
    await db
        .into(db.fitnessTests)
        .insert(FitnessTestsCompanion.insert(round: 3, item: 'hollow_hold', value: 99, date: '2026-02-30'));
    final result = await read();
    expect(result.axis(RadarAxis.legs).current!.value, 20);
    expect(result.axis(RadarAxis.legs).latestObserved!.eligible, isFalse);
    expect(result.axis(RadarAxis.pull).current!.value, 8);
    expect(result.axis(RadarAxis.pull).observations.length, 2);
    expect(result.axis(RadarAxis.core).current!.value, 35);
    expect(result.axis(RadarAxis.core).observations.any((o) => o.date == null), isTrue);
  });
  test('Cindy flags/ventana/receta y orden DDFFSS son observaciones', () async {
    await seedRadarSql(db);
    final originals = [
      radarCindy(day: 10, total: 420, incomplete: true),
      radarCindy(day: 10, total: 1501),
      radarCindy(day: 10, total: 2100),
      radarCindy(day: 10, mode: 'tabata'),
      radarCindy(day: 10, imported: true),
      radarCindy(day: 10, estimated: true),
      radarCindy(day: 10, technique: false),
      radarCindy(day: 10, sets: const [CindySet(exercise: 'Dominadas', reps: 5)]),
      radarCindy(day: 10, rounds: 2, extra: 0, sets: const [
        CindySet(exercise: 'Dominadas', reps: 5),
        CindySet(exercise: 'Dominadas', reps: 5),
        CindySet(exercise: 'Flexiones', reps: 10),
        CindySet(exercise: 'Flexiones', reps: 10),
        CindySet(exercise: 'Sentadillas', reps: 15),
        CindySet(exercise: 'Sentadillas', reps: 15)
      ]),
      radarCindy(day: 10, rounds: 1, extra: 0, sets: const [
        CindySet(exercise: 'Dominadas', reps: 5, loadKg: 2),
        CindySet(exercise: 'Flexiones', reps: 10),
        CindySet(exercise: 'Sentadillas', reps: 15)
      ]),
      radarCindy(day: 10, rounds: 1, extra: 0, sets: const [
        CindySet(exercise: 'Dominadas', reps: 5, variant: 'supina'),
        CindySet(exercise: 'Flexiones', reps: 10),
        CindySet(exercise: 'Sentadillas', reps: 15)
      ]),
    ];
    for (final row in originals) {
      await insertCindySql(db, row);
    }
    await insertCindySql(db, radarCindy(), rawDate: '2026-13-99');
    final circuit = (await read()).axis(RadarAxis.circuit);
    expect(circuit.current!.value, 8.5);
    expect(circuit.observations.length, 14);
    expect(circuit.observations.where((o) => o.eligible).length, 2);
    expect(circuit.observations.where((o) => o.cindy?.totalSec == 1501).single.reason, contains('Ventana real'));
    final ddffss = circuit.observations.firstWhere((o) => o.cindy?.rounds == 2);
    expect(ddffss.eligible, isFalse);
    expect(ddffss.cindy!.sets.map((s) => s.exercise),
        ['Dominadas', 'Dominadas', 'Flexiones', 'Flexiones', 'Sentadillas', 'Sentadillas']);
  });
  test('300 sesiones por lotes equivalen a core completo sin perder inicio', () async {
    final observations = <CindyObservation>[];
    await db.transaction(() async {
      for (var i = 0; i < 300; i++) {
        final row = radarCindy(day: i == 0 ? 1 : 9, rounds: i == 0 ? 2 : 3, extra: 0);
        final id = await insertCindySql(db, row);
        observations.add(CindyObservation(
            id: '$id',
            date: row.date,
            type: row.type,
            mode: row.mode,
            totalSec: row.totalSec,
            warmupSec: row.warmupSec,
            cooldownSec: row.cooldownSec,
            rounds: row.rounds,
            extraReps: row.extraReps,
            sets: row.sets,
            imported: false,
            estimated: false,
            incomplete: false));
      }
    });
    final actual = (await read()).axis(RadarAxis.circuit);
    final direct = buildPersonalRadar(tests: await FitnessTestRepository(db).all(), cindy: observations, asOf: radarDay)
        .axis(RadarAxis.circuit);
    expect(actual.observations.map((o) => (o.sourceKey, o.raw, o.eligible)),
        direct.observations.map((o) => (o.sourceKey, o.raw, o.eligible)));
    expect(actual.firstEligible!.value, 2);
    expect(actual.current!.value, 3);
    expect(actual.observations.length, 300);
  });
  test('ZIP restore SQLite y databaseGeneration releen referencias del radar', () async {
    final dir = Directory.systemTemp.createTempSync('seguimiento-011-ficticio-');
    final data = Directory('${dir.path}/data')..createSync();
    final host =
        DatabaseHost(File('${data.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)), initial: db);
    await seedRadarSql(db);
    final archive = BackupArchive(host: host, documents: data);
    final saved = await archive.exportTo('${dir.path}/saved.zip');
    await goals.setReference(GoalMetric.refDominadas, 20, now: radarDay);
    final container = ProviderContainer(
        overrides: [databaseHostProvider.overrideWithValue(host), todayProvider.overrideWith(_Today.new)]);
    final sub = container.listen(personalRadarProvider('2026-10-10'), (_, __) {});
    try {
      expect(
          (await container.read(personalRadarProvider('2026-10-10').future)).axis(RadarAxis.pull).currentPercent, 40);
      await archive.restoreFrom(saved.file);
      db = host.db;
      goals = GoalRepository(db);
      repo = PersonalRadarRepository(db);
      container.read(databaseGenerationProvider.notifier).state++;
      expect(
          (await container.read(personalRadarProvider('2026-10-10').future)).axis(RadarAxis.pull).currentPercent, 80);
      expect((await db.select(db.goalVersions).get()).where((v) => v.metric == 'refDominadas').single.value, 10);
    } finally {
      sub.close();
      container.dispose();
    }
    // Preserve synthetic capsule under QA output; no owner paths involved.
    await saved.file.copy('build/qa/011/refs-roundtrip.zip');
  });
  test('providers observan editar/borrar evidencia antigua y referencias sin invalidación manual', () async {
    await seedRadarSql(db, complete: false);
    await (db.update(db.fitnessTests)..where((r) => r.round.equals(1)))
        .write(const FitnessTestsCompanion(date: Value('2026-01-01')));
    final container = ProviderContainer(overrides: [
      databaseHostProvider
          .overrideWithValue(DatabaseHost(File('unused.sqlite'), (_) => openInMemoryDatabase(), initial: db)),
      todayProvider.overrideWith(_Today.new)
    ]);
    final subscription = container.listen(personalRadarProvider('2026-10-10'), (_, __) {});
    try {
      Future<PersonalRadar> settled() async {
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          final state = container.read(personalRadarProvider('2026-10-10'));
          if (!state.isLoading && state.hasValue) return state.requireValue;
        }
        throw StateError('Radar no settled');
      }

      expect((await settled()).axis(RadarAxis.pull).firstEligible!.value, 5);
      await (db.update(db.fitnessTests)..where((r) => r.round.equals(1) & r.item.equals('pullup')))
          .write(const FitnessTestsCompanion(value: Value(0)));
      expect((await settled()).axis(RadarAxis.pull).firstEligible!.value, 0);
      expect((await settled()).axis(RadarAxis.pull).changePercent, isNull);
      await (db.delete(db.fitnessTests)..where((r) => r.round.equals(1) & r.item.equals('pullup'))).go();
      expect((await settled()).axis(RadarAxis.pull).firstEligible!.value, 8);
      await goals.setReference(GoalMetric.refDominadas, 4, now: radarDay);
      expect((await settled()).axis(RadarAxis.pull).currentPercent, 200);
    } finally {
      subscription.close();
      container.dispose();
    }
  });
}
