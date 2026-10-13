import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/coach_repository.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/daily_routines.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/features/home/readiness_card.dart';

import '../support/sqlite_host.dart';

/// Revisión R1 de 032: una rutina guardada a medias no cuenta como hecha, las
/// dos opciones de "RPE > 5" guardan lo que dicen y una molestia anotada
/// después de la rutina llega a Hoy sola.
void main() {
  late AppDatabase db;
  late TrainingRepository training;
  late ReadinessRepository repo;
  final mon = DateTime(2030, 3, 4);

  setUpAll(useHostSqlite);

  setUp(() {
    db = openInMemoryDatabase();
    training = TrainingRepository(db, ExerciseRepository(db));
    repo = ReadinessRepository(db);
  });

  tearDown(() => db.close());

  Future<void> routine(DateTime d, String mode, {required bool complete, int? rpe}) => training.save(SessionDraft(
      date: d, type: SessionType.movilidad, mode: mode, totalSec: complete ? 1800 : 40, incomplete: !complete, rpe: rpe));

  test('a medias: queda guardada pero no es recuperación hecha, ni ✓, ni racha', () async {
    await routine(mon, recoveryActiveId, complete: false);
    await routine(mon, morningActivaId, complete: false);
    expect(await db.select(db.sessions).get(), hasLength(2), reason: 'el registro parcial se conserva');
    expect(await repo.recoveryDone(mon), isFalse);
    expect(await repo.routinesOn(mon), isEmpty);
    expect(await repo.mobilityStreak(mon), 0);

    await routine(mon, morningActivaId, complete: true);
    expect(await repo.routinesOn(mon), {morningActivaId});
    expect(await repo.recoveryDone(mon), isFalse);
    await routine(mon, recoveryActiveId, complete: true);
    expect(await repo.recoveryDone(mon), isTrue);
    expect(await repo.mobilityStreak(mon), 1);
  });

  test('RPE > 5: "Sesión normal" suma carga; "Recuperación" no', () async {
    // Lo que guarda cada botón del diálogo (mobility_screen.startMobility).
    await training.save(SessionDraft(date: mon, type: SessionType.otro, totalSec: 1800, rpe: 7, notes: 'Recuperación activa'));
    await routine(mon, recoveryActiveId, complete: true, rpe: 7);
    final items = await CoachRepository(db).loadItems(mon);
    expect([for (final i in items) (i.minutes, i.effort)], [(30, 7)], reason: 'sólo la guardada como sesión normal');
    expect(await repo.recoveryDone(mon), isTrue, reason: 'la que quedó como recuperación sigue siéndolo');
  });

  test('el provider real de Hoy se recalcula solo: "Entrenar igual" y la recuperación terminada', () async {
    final dir = Directory.systemTemp.createTempSync('seguimiento_032_view');
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      localFlagsProvider.overrideWithValue(LocalFlags(File('${dir.path}/flags.json'))),
    ]);
    addTearDown(container.dispose);
    final key = (day: dayKey(mon), test: false);
    final sub = container.listen(readinessViewProvider(key), (_, __) {});
    addTearDown(sub.close);
    for (final (d, min, effort) in [(DateTime(2030, 3, 2), 60, 5), (DateTime(2030, 3, 3), 90, 7), (DateTime(2030, 3, 3), 60, 8)]) {
      await db.into(db.footballGames).insert(FootballGamesCompanion.insert(date: dayKey(d), minutes: min, intensity: Value(effort)));
    }
    await pumpEventQueue();
    var v = await container.read(readinessViewProvider(key).future);
    expect(v.proposesRecovery, isTrue);

    await routine(mon, recoveryActiveId, complete: false);
    await pumpEventQueue();
    v = await container.read(readinessViewProvider(key).future);
    expect((v.recoveryDone, v.proposesRecovery), (false, true), reason: 'a medias sigue proponiendo');

    await repo.trainAnyway(mon, v.advice);
    await pumpEventQueue();
    v = await container.read(readinessViewProvider(key).future);
    expect((v.trainedAnyway, v.proposesRecovery), (true, false));

    await routine(mon, morningActivaId, complete: true);
    await pumpEventQueue();
    v = await container.read(readinessViewProvider(key).future);
    expect(v.routines, {morningActivaId}, reason: 'el ✓ de la mañana llega sin recargar');
  });

  group('racha de constancia', () {
    late DashboardRepository dashboard;
    final today = dateOnly(DateTime.now());

    setUp(() async {
      final plan = PlanRepository(db, ExerciseRepository(db));
      dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
      await seedIfEmpty(db, plan);
    });

    test('la recuperación a medias no mantiene la racha; terminada sí', () async {
      await routine(today, recoveryActiveId, complete: false);
      expect((await dashboard.today(now: today)).streak, 0);
      await routine(today, recoveryActiveId, complete: true);
      expect((await dashboard.today(now: today)).streak, 1);
    });

    test('una molestia anotada después llega a Hoy sin otra acción', () async {
      final dir = Directory.systemTemp.createTempSync('seguimiento_032_signals');
      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        localFlagsProvider.overrideWithValue(LocalFlags(File('${dir.path}/flags.json'))),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(dashboardProvider, (_, __) {});
      addTearDown(sub.close);
      final recovery = RecoveryRepository(db);
      await recovery.setSoreness(addDays(today, -2), {'Isquios': 5});
      await recovery.setSoreness(addDays(today, -1), {'Isquios': 5});
      final before = await container.read(dashboardProvider.future);
      expect(before.soreZones, isNot(contains('Isquios')), reason: 'dos días todavía no es "no baja en 3"');

      // Lo que hace "¿Algo tirante o con molestia?" al terminar la rutina.
      await recovery.addSoreness(today, 'Isquios', 6);
      await pumpEventQueue();
      final after = await container.read(dashboardProvider.future);
      expect(after.soreZones, contains('Isquios'));
    });
  });
}
