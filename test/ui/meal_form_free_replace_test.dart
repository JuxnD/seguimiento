import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/seed_foods.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/features/meals/meal_form_screen.dart';

import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

/// C01 en pantalla: una entrada libre con el nombre de un alimento por 100 g
/// no ofrece "Actualizar"; guardarla como nueva deja intactos el alimento y
/// sus combos.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useHostSqlite);

  // La base corre en otro isolate: dejar que conteste antes de asentar.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('entrada libre homónima de un alimento por 100 g: sin "Actualizar" y el combo no cambia',
      (tester) async {
    await loadTestFonts(tester);
    final db = openInMemoryDatabase();
    await tester.runAsync(() => seedFoodsIfEmpty(db));
    final nutrition = NutritionRepository(db);
    final rice = (await tester.runAsync(() => nutrition.foodNamed('Arroz blanco cocido')))!;
    final before = (await tester.runAsync(() => nutrition.templates()))!
        .firstWhere((t) => t.name == 'Almuerzo típico')
        .macros
        .kcal;
    final host = DatabaseHost(File('unused.sqlite'), (_) => openInMemoryDatabase(), initial: db);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseHostProvider.overrideWithValue(host)],
      child: MaterialApp(
        home: MealFormScreen(
          draft: MealDraft(date: DateTime(2026, 10, 9), time: '13:00', slot: MealSlot.almuerzo),
        ),
      ),
    ));
    await settle(tester);

    final freeEntry = find.byTooltip('Entrada libre');
    await tester.ensureVisible(freeEntry);
    await settle(tester);
    expect(freeEntry.hitTestable(), findsOneWidget);
    await tester.tap(freeEntry);
    await settle(tester);
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Arroz blanco cocido');
    await tester.enterText(fields.at(1), '500');
    await tester.pump();
    await tester.tap(find.text('Añadir'));
    await settle(tester);

    expect(find.text('«Arroz blanco cocido» ya está en el catálogo'), findsOneWidget);
    expect(find.text('Actualizar'), findsNothing);
    expect(find.textContaining('no por porción'), findsOneWidget);
    await tester.tap(find.text('Guardar como nuevo'));
    await settle(tester);

    final after = (await tester.runAsync(() => nutrition.foodById(rice.id)))!;
    expect((after.basis, after.unitLabel, after.kcal), (FoodBasis.per100, rice.unitLabel, rice.kcal));
    final copy = await tester.runAsync(() => nutrition.foodNamed('Arroz blanco cocido (2)'));
    expect(copy?.unitLabel, 'porción');
    final comboAfter = (await tester.runAsync(() => nutrition.templates()))!
        .firstWhere((t) => t.name == 'Almuerzo típico')
        .macros
        .kcal;
    expect(comboAfter, before);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });
}
