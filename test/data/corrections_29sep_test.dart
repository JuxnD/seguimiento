import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/corrections_29sep.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';

import '../support/sqlite_host.dart';

/// Correcciones de datos del traspaso del 29 sep (§17).
void main() {
  late AppDatabase db;
  late TrainingRepository training;
  late NutritionRepository nutrition;

  DateTime d(int month, int day) => DateTime(2026, month, day);
  MealItemDraft item(String label, double kcal, double protein, {double? qty, double carbs = 0, double fat = 0}) =>
      MealItemDraft(
        label: label,
        quantity: qty,
        quantityUnit: qty == null ? null : 'g',
        macros: Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat),
      );

  setUpAll(useHostSqlite);

  setUp(() async {
    db = openInMemoryDatabase();
    training = TrainingRepository(db, ExerciseRepository(db));
    nutrition = NutritionRepository(db);
    await db.into(db.profiles).insert(ProfilesCompanion.insert(startDate: '2026-08-26'));
  });

  tearDown(() => db.close());

  /// Los registros tal como estaban el 29 sep.
  Future<void> seedAsOn29Sep() async {
    await training.save(SessionDraft(date: d(9, 23), type: SessionType.circuitoLigero, rpe: 10));
    await training.save(SessionDraft(date: d(9, 24), type: SessionType.bloques));
    await training.save(SessionDraft(date: d(9, 25), type: SessionType.progresion, roundsDone: 8));
    await training.save(SessionDraft(date: d(9, 28), type: SessionType.circuito, sets: [
      SetDraft(exercise: 'Plancha lateral', reps: 0),
      SetDraft(exercise: 'Plancha lateral', reps: 0),
      SetDraft(exercise: 'Flexiones', reps: 10),
    ]));
    // Desayuno del 28: salchichón de 200 g (1.140 kcal en total).
    await nutrition.saveMeal(MealDraft(date: d(9, 28), slot: MealSlot.desayuno, time: '08:10', items: [
      item('Huevo (unidad)', 210, 18, carbs: 1.2, fat: 15),
      item('Pan Mipan', 248, 7.2, qty: 75, carbs: 43.5, fat: 5.4),
      item('Salchichón de pollo', 400, 26, qty: 200, carbs: 6, fat: 30),
      item('Leche entera', 282, 23.8, qty: 400, carbs: 21.7, fat: 22.9),
    ]));
    await nutrition.saveMeal(MealDraft(date: d(9, 25), slot: MealSlot.merienda, time: '16:47', items: [
      item('Huevos + pan + leche', 700, 40),
    ]));
    await nutrition.saveMeal(MealDraft(date: d(9, 27), slot: MealSlot.cena, time: '19:48', items: [
      item('Almuerzo', 650, 34),
      item('Cena', 1100, 49),
    ]));
    await nutrition.saveMeal(MealDraft(date: d(9, 28), slot: MealSlot.merienda, time: '16:10', items: [
      item('Pasta', 900, 35),
    ]));
    // Duplicado accidental del 29.
    await nutrition.saveMeal(MealDraft(date: d(9, 29), slot: MealSlot.desayuno, time: '15:51', items: [
      item('Desayuno 1', 1140, 75),
    ]));
  }

  Future<SessionRow> session(String date) =>
      (db.select(db.sessions)..where((t) => t.date.equals(date))).getSingle();

  test('con los datos del 29 sep, todas quedan por aplicar', () async {
    await seedAsOn29Sep();
    final states = await checkCorrections(db);
    expect(states.values.toSet(), {CorrectionState.pending}, reason: '$states');
    expect(states, hasLength(corrections29Sep.length));
  });

  test('aplicarlas deja cada registro como pide el traspaso', () async {
    await seedAsOn29Sep();
    expect(await applyPendingCorrections(db), corrections29Sep.length);

    expect((await session('2026-09-23')).rpe, 4);
    expect((await session('2026-09-24')).rpe, 6);
    final friday = await session('2026-09-25');
    expect(friday.rpe, 7);
    expect(friday.notes, 'Flexiones y dominadas fáciles hasta R8, técnica constante');

    final monday = await training.load((await session('2026-09-28')).id);
    expect(monday.sets.where((s) => s.exercise == 'Plancha lateral').map((s) => s.reps), [40, 40]);
    expect(monday.sets.firstWhere((s) => s.exercise == 'Flexiones').reps, 10, reason: 'lo demás no se toca');

    final m28 = await nutrition.range(d(9, 28), d(9, 28));
    final breakfast = m28.singleWhere((m) => m.meal.slot == MealSlot.desayuno);
    expect(breakfast.macros.kcal, closeTo(960, 0.5));
    expect(breakfast.macros.protein, closeTo(63, 0.5));
    expect(breakfast.items.firstWhere((i) => i.label.startsWith('Salchichón')).quantity, 110);
    expect(m28.map((m) => (m.meal.slot, m.meal.time)), contains((MealSlot.almuerzo, '16:10')));

    final m25 = await nutrition.range(d(9, 25), d(9, 25));
    expect(m25.single.meal.slot, MealSlot.desayuno);

    final m27 = await nutrition.range(d(9, 27), d(9, 27));
    final lunch = m27.singleWhere((m) => m.meal.slot == MealSlot.almuerzo);
    final dinner = m27.singleWhere((m) => m.meal.slot == MealSlot.cena);
    expect((lunch.macros.kcal, lunch.macros.protein), (650, 34));
    expect((dinner.macros.kcal, dinner.macros.protein), (1100, 49));
    expect(lunch.items.single.label, 'Sopa de mondongo + arroz');
    expect(dinner.items.single.label, 'Pasta con queso y salchicha (plato grande)');

    expect(await nutrition.range(d(9, 29), d(9, 29)), isEmpty, reason: 'el duplicado se borra');
    final closed = {for (final c in await db.select(db.closedDays).get()) c.date};
    expect(closed, {'2026-09-25', '2026-09-27', '2026-09-28'}, reason: 'solo los días con comidas');

    final again = await checkCorrections(db);
    expect(again.values.toSet(), {CorrectionState.done}, reason: '$again');
    expect(await applyPendingCorrections(db), 0, reason: 'aplicar dos veces no cambia nada');
  });

  test('lo que el usuario ya corrigió a mano distinto no se pisa', () async {
    await seedAsOn29Sep();
    // RPE del 23 corregido a 5 por el usuario; el desayuno del 29 era suyo
    // de verdad (otra hora).
    final s23 = await session('2026-09-23');
    await (db.update(db.sessions)..where((t) => t.id.equals(s23.id))).write(const SessionsCompanion(rpe: Value(5)));
    final dup = (await nutrition.range(d(9, 29), d(9, 29))).single;
    await nutrition.updateMealHeader(dup.meal.id, time: '07:30');

    final states = await checkCorrections(db);
    expect(states['rpe-23'], CorrectionState.missing);
    expect(states['duplicado-29'], CorrectionState.done);
    await applyPendingCorrections(db);

    expect((await session('2026-09-23')).rpe, 5);
    expect(await nutrition.range(d(9, 29), d(9, 29)), hasLength(1), reason: 'otra hora: no es el duplicado');
  });

  test('sin esos registros no se toca nada', () async {
    final states = await checkCorrections(db);
    expect(states['rpe-23'], CorrectionState.missing);
    expect(states['desayuno-28'], CorrectionState.missing);
    expect(states['cerrar-24-28'], CorrectionState.missing, reason: 'sin comidas no hay días que cerrar');
    expect(await applyPendingCorrections(db), 0);
  });
}
