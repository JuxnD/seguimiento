import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late TrainingRepository repo;
  setUp(() { db = openInMemoryDatabase(); repo = TrainingRepository(db, ExerciseRepository(db)); });
  tearDown(() => db.close());
  SessionDraft draft(DateTime date) => SessionDraft(date: date, type: SessionType.trenSuperior, sets: [
    SetDraft(exercise: 'Flexiones', reps: 8, loadKg: 5, variant: 'neutra', rir: 2,
      split: true, splitDetail: '4+4'), SetDraft(exercise: 'Remo', reps: 7),
  ]);
  final before = DateTime(2026, 9, 4), day = DateTime(2026, 9, 11);
  test('lista completa idéntica encuentra previo; editar propio id no se compara consigo', () async {
    final old = draft(before);
    await repo.save(old);
    expect((await repo.repeatedSetsBefore(draft(day)))!.id, old.id);
    expect(await repo.repeatedSetsBefore(old), isNull);
  });
  for (final field in ['última serie', 'carga', 'variante', 'RIR', 'split', 'detalle', 'fallo', 'orden']) {
    test('diferencia en $field evita falso duplicado', () async {
      await repo.save(draft(before));
      final current = draft(day);
      if (field == 'última serie') current.sets.last.reps = 6;
      if (field == 'carga') current.sets.first.loadKg = 0;
      if (field == 'variante') current.sets.first.variant = 'prona';
      if (field == 'RIR') current.sets.first.rir = null;
      if (field == 'split') current.sets.first.split = false;
      if (field == 'detalle') current.sets.first.splitDetail = '3+5';
      if (field == 'fallo') current.sets.first.toFailure = true;
      if (field == 'orden') { final first = current.sets.removeAt(0); current.sets.add(first); }
      expect(await repo.repeatedSetsBefore(current), isNull);
    });
  }
  test('plantillas distintas no coinciden por tipo o weekday', () async {
    final plan = PlanRepository(db, ExerciseRepository(db));
    await plan.saveAsNewVersion(PlanDraft.empty(DateTime(2026, 9, 1)));
    final days = await db.select(db.planDays).get();
    await repo.save(draft(before)..planDayId = days[0].id);
    expect(await repo.repeatedSetsBefore(draft(day)..planDayId = days[1].id), isNull);
  });
  test('vacío y carga null frente a cero no son duplicados', () async {
    expect(await repo.repeatedSetsBefore(SessionDraft(date: day)), isNull);
    final old = draft(before)..sets.first.loadKg = null;
    await repo.save(old);
    expect(await repo.repeatedSetsBefore(draft(day)..sets.first.loadKg = 0), isNull);
  });
  for (final reason in ['estimado', 'importado', 'incompleto', 'sin calidad']) {
    test('diez $reason no acredita hito limpio', () async {
      final ten = SessionDraft(date: day, type: SessionType.progresion, roundsDone: 10, plannedRounds: 10,
        techniqueOk: true, fullRange: true, recoveryOk: true);
      if (reason == 'estimado') ten.roundsEstimated = true;
      if (reason == 'importado') ten.imported = true;
      if (reason == 'incompleto') ten.incomplete = true;
      if (reason == 'sin calidad') ten.techniqueOk = null;
      await repo.save(ten);
      expect(await repo.firstCleanTen(), isNull);
    });
  }
  test('hito excluye propioID y exige contexto legado, no plan desconocido/guiado sin vínculo', () async {
    final ten = SessionDraft(date: day, type: SessionType.progresion, roundsDone: 10, plannedRounds: 10,
      techniqueOk: true, fullRange: true, recoveryOk: true);
    await repo.save(ten);
    expect(await repo.firstCleanTen(excludeSessionId: ten.id), isNull);
    expect(await repo.firstCleanTen(), day);
    expect(await repo.v2ProgressionContext(ten), isFalse);
    final plan = PlanDraft.empty(DateTime(2026, 9, 1));
    plan.days[4].type = DayType.progresion;
    final plans = PlanRepository(db, ExerciseRepository(db));
    await plans.saveAsNewVersion(plan);
    expect(await repo.v2ProgressionContext(ten), isTrue);
    expect(await repo.v2ProgressionContext(ten, requireLink: true), isFalse);
    ten.planDayId = (await plans.dayFor(day))!.dayId;
    expect(await repo.v2ProgressionContext(ten, requireLink: true), isTrue);
  });
}
