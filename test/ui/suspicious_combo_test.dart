import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/features/meals/meals_screen.dart';

import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

/// C01: un combo con cantidad sospechosa pregunta antes de registrarse; no
/// se bloquea, porque puede ser real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useHostSqlite);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('combo con 150 porciones: pregunta y "Registrar igual" lo registra', (tester) async {
    await loadTestFonts(tester);
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = openInMemoryDatabase();
    final nutrition = NutritionRepository(db);
    await tester.runAsync(() async {
      final id = await nutrition.saveFreeEntryFood('Arroz chino', const Macros(kcal: 400, protein: 12));
      await nutrition.saveTemplate('Inflado', null, [(id, 150)]);
    });
    final host = DatabaseHost(File('unused.sqlite'), (_) => openInMemoryDatabase(), initial: db);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseHostProvider.overrideWithValue(host)],
      child: const MaterialApp(home: MealsScreen()),
    ));
    await settle(tester);

    final tile = find.text('Inflado');
    await tester.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Revisa: 150 porciones de Arroz chino'), findsOneWidget);
    await tester.tap(tile);
    await settle(tester);
    expect(find.text('¿Revisar «Inflado»?'), findsOneWidget);
    expect(find.text('Corregir combo'), findsOneWidget);

    await tester.tap(find.text('Registrar igual'));
    await settle(tester);
    // Sigue el flujo normal de un toque (confirmar franja si la pide).
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      final confirm = find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton));
      if (confirm.evaluate().isNotEmpty) await tester.tap(confirm.first);
      await settle(tester);
    }
    final meals = await tester.runAsync(() => db.select(db.meals).get());
    expect(meals, hasLength(1), reason: 'la cantidad sospechosa no bloquea el registro');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });
}
