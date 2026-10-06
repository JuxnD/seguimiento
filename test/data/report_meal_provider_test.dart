import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';

import '../support/sqlite_host.dart';

typedef _MealSnapshot = ({double? previousProtein, Set<String> previousClosed});

void main() {
  setUpAll(useHostSqlite);

  test(
      'el informe observa macros con kcal constante y cierre del período previo',
      () async {
    final db = openInMemoryDatabase();
    final nutrition = NutritionRepository(db);
    final container =
        ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    const range = ('2026-10-05', '2026-10-11');
    const previousDay = '2026-10-01';
    final initial = Completer<void>();
    var settled = Completer<_MealSnapshot>();
    var expectedProtein = -1.0;
    var expectedClosed = const <String>{};
    final sub = container.listen(reportInputProvider(range), (_, next) {
      final input = next.valueOrNull;
      if (input == null) return;
      final previous = input.previous;
      final protein = previous == null || previous.meals.isEmpty
          ? null
          : previous.meals.first.items.first.macros.protein;
      if (!initial.isCompleted && input.meals.isEmpty && (protein == null)) {
        initial.complete();
      }
      if (initial.isCompleted &&
          protein == expectedProtein &&
          previous!.closedDays.contains(previousDay) ==
              expectedClosed.contains(previousDay) &&
          !settled.isCompleted) {
        settled.complete((
          previousProtein: protein,
          previousClosed: previous.closedDays,
        ));
      }
    }, fireImmediately: true);
    addTearDown(sub.close);

    await container.read(reportInputProvider(range).future);
    await initial.future.timeout(const Duration(seconds: 5));
    expectedProtein = 10;
    final firstMeal = settled.future.timeout(const Duration(seconds: 5));
    final id = await nutrition.saveMeal(MealDraft(
      date: DateTime(2026, 10, 1),
      slot: MealSlot.desayuno,
      notes: 'nota inicial',
      items: [
        MealItemDraft(
          label: 'Comida sintética',
          macros: const Macros(kcal: 250, protein: 10, carbs: 30, fat: 5),
        ),
      ],
    ));
    expect((await firstMeal).previousProtein, 10);

    final item = await (db.select(db.mealItems)
          ..where((row) => row.mealId.equals(id)))
        .getSingle();
    expectedProtein = 12;
    settled = Completer<_MealSnapshot>();
    final editedMeal = settled.future.timeout(const Duration(seconds: 5));
    await (db.update(db.mealItems)..where((row) => row.id.equals(item.id)))
        .write(const MealItemsCompanion(
      kcal: Value(250),
      protein: Value(12),
    ));
    expect((await editedMeal).previousProtein, 12);

    expectedClosed = const {previousDay};
    settled = Completer<_MealSnapshot>();
    final closed = settled.future.timeout(const Duration(seconds: 5));
    await nutrition.setClosed(DateTime(2026, 10, 1), true);
    expect((await closed).previousClosed, contains(previousDay));

    expectedClosed = const {};
    settled = Completer<_MealSnapshot>();
    final reopened = settled.future.timeout(const Duration(seconds: 5));
    await nutrition.setClosed(DateTime(2026, 10, 1), false);
    expect((await reopened).previousClosed, isNot(contains(previousDay)));
  });
}
