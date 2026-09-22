import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/app.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';

import '../support/sqlite_host.dart';

/// Humo de la app completa: que cada pestaña arme con datos reales.
///
/// En Windows queda saltado: `flutter_tester` se cuelga al cargar la SQLite
/// del sistema (`winsqlite3.dll`). Con una `sqlite3.dll` propia en el PATH, o
/// en macOS/Linux, corre normal. Ver docs/project-map.md (riesgos).
final _skipReason = Platform.isWindows
    ? 'flutter_tester se cuelga con winsqlite3.dll; correr en macOS/Linux o con sqlite3.dll propia'
    : null;

void main() {
  setUpAll(useHostSqlite);

  late AppDatabase db;

  setUp(() => db = openInMemoryDatabase());
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Desmonta el árbol dentro del test: al cancelar los streams, drift agenda
  /// timers de duración cero que deben correr antes de terminar.
  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const SeguimientoApp(),
      ),
    );
    // pumpAndSettle no sirve: los indicadores de carga animan sin fin.
    await settle(tester);
  }

  testWidgets(skip: _skipReason, 'arranca en Hoy y navega por todas las pestañas', (tester) async {
    await pumpApp(tester);
    expect(find.text('Hoy'), findsWidgets);
    expect(find.textContaining('Semana'), findsWidgets);

    for (final tab in ['Entreno', 'Comidas', 'Cuerpo', 'Informe']) {
      await tester.tap(find.text(tab));
      await settle(tester);
      expect(find.text(tab), findsWidgets, reason: 'no abrió $tab');
    }
    await disposeApp(tester);
  });

  testWidgets(skip: _skipReason, 'el informe se genera con los datos registrados', (tester) async {
    await NutritionRepository(db).saveMeal(
      MealDraft(date: DateTime.now(), slot: MealSlot.almuerzo)
        ..items.add(MealItemDraft(label: 'Bandeja', macros: const Macros(kcal: 1500, protein: 50))),
    );

    await pumpApp(tester);
    await tester.tap(find.text('Informe'));
    await settle(tester);

    expect(find.textContaining('# Informe semanal'), findsOneWidget);
    expect(find.textContaining('Bandeja'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets(skip: _skipReason, 'la pestaña Comidas muestra el total del día', (tester) async {
    await NutritionRepository(db).saveMeal(
      MealDraft(date: DateTime.now(), slot: MealSlot.desayuno)
        ..items.add(MealItemDraft(label: 'Huevo', quantity: 3, quantityUnit: 'huevo', macros: const Macros(kcal: 216, protein: 19))),
    );

    await pumpApp(tester);
    await tester.tap(find.text('Comidas'));
    await settle(tester);

    expect(find.textContaining('216 kcal de'), findsOneWidget);
    expect(find.textContaining('Huevo'), findsOneWidget);
    await disposeApp(tester);
  });
}
