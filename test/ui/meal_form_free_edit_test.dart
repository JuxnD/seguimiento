import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/features/meals/meal_form_screen.dart';

import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useHostSqlite);

  testWidgets(
      'editar una estimación coincidente no enlaza ni verifica catálogo antes de Guardar',
      (tester) async {
    await loadTestFonts(tester);
    final db = openInMemoryDatabase();
    final foodId = await db.into(db.foods).insert(FoodsCompanion.insert(
          name: 'Yogur',
          basis: FoodBasis.unit,
          kcal: 150,
          protein: 10,
          carbs: const Value(20),
          fat: const Value(2),
          source: const Value(MacroSource.etiqueta),
        ));
    final originalFoods = await db.select(db.foods).get();
    final host = DatabaseHost(
        File('unused.sqlite'), (_) => openInMemoryDatabase(),
        initial: db);
    var saved = false;
    final draft = MealDraft(
      date: DateTime(2026, 10, 6),
      time: '12:00',
      slot: MealSlot.otro,
      items: [
        MealItemDraft(
          label: 'Yogur',
          quantity: 1,
          quantityUnit: 'porción',
          macros: const Macros(kcal: 150, protein: 10, carbs: 20, fat: 2),
          sourceVerified: null,
        )
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseHostProvider.overrideWithValue(host)],
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                      child: const Text('Abrir comida'),
                      onPressed: () async {
                        saved = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        MealFormScreen(draft: draft))) ??
                            false;
                      },
                    ),
                  ))),
    ));
    await tester.tap(find.text('Abrir comida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yogur ×1 porción'));
    await tester.pumpAndSettle();
    expect(find.text('«Yogur» ya está en el catálogo'), findsNothing);
    await tester.tap(find.text('Guardar').last);
    await tester.pumpAndSettle();
    expect(find.text('estimado · 150 kcal · P 10 g · C 20 g · G 2 g'),
        findsOneWidget);
    expect(await db.select(db.meals).get(), isEmpty);
    expect(await db.select(db.foods).get(), originalFoods);

    final save = find.text('Guardar');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(await db.select(db.foods).get(), originalFoods);
    final persisted = await db.select(db.mealItems).getSingle();
    expect(persisted.foodId, isNull);
    expect(persisted.sourceVerified, isNull);
    expect(persisted.kcal, 150);
    expect(await db.select(db.foods).get(), hasLength(1));
    expect(foodId, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  });
}
