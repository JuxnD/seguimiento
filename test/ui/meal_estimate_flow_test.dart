import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/data/seed_foods.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/features/meals/meal_form_screen.dart';
import 'package:seguimiento/features/meals/meal_text_screen.dart';
import '../support/meal_estimate_fixture.dart';
import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

class _Activation extends AiActivation {
  @override
  Future<(String, String)> read() async =>
      ('SEG-FICTICIO', 'AAAA-BBBB-CCCC-DDDD');
}

http.Response _reply(String task, Object result) => http.Response(
    jsonEncode({
      'status': 'success',
      'contract': 2,
      'task': task,
      'model': 'gpt-6-luna',
      'result': result
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useHostSqlite);
  testWidgets(
      'estimación de 250 g no permite convertir la unidad a porción o ml',
      (tester) async {
    await loadTestFonts(tester);
    await tester.binding.setSurfaceSize(const Size(460, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const phrase = '250 g de arroz chino';
    MockClient clientFactory() => MockClient((request) async {
          final task = (jsonDecode(request.body) as Map)['task'] as String;
          return _reply(
              task,
              task == 'status'
                  ? {
                      'enabled': true,
                      'tasks': ['meal_estimate']
                    }
                  : estimateResult(
                      [estimateItem('Arroz chino')], [(phrase, 0)]));
        });
    await tester.pumpWidget(MaterialApp(
        home: MealTextScreen(
            foods: const [],
            activation: _Activation(),
            clientFactory: clientFactory)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Describe la comida'), phrase);
    await tester.pump();
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
        .onChanged!(true);
    await tester.pump();
    await tester.ensureVisible(find.text('Preparar borrador'));
    await tester.tap(find.text('Preparar borrador'));
    await tester.pumpAndSettle();
    final unitFinder = find.widgetWithText(
        TextField, 'Unidad de esta porción (g, ml, porción…)');
    final unitField = tester.widget<TextField>(unitFinder);
    expect(unitField.readOnly, isTrue,
        reason: 'Cambiar g por porción/ml no es una conversión conocida.');
    final confirm = find.byKey(const Key('estimate-confirm-0'));
    for (final incompatible in ['porción', 'ml']) {
      unitField.controller!.text = incompatible;
      await tester.ensureVisible(find.byKey(const Key('estimate-0-Cantidad')));
      await tester.enterText(find.byKey(const Key('estimate-0-Cantidad')), '1');
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(confirm).onChanged, isNull);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Añadir al borrador'))
              .onPressed,
          isNull);
    }
    unitField.controller!.text = 'g';
    await tester.enterText(find.byKey(const Key('estimate-0-Cantidad')), '125');
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(confirm).onChanged, isNotNull);
    expect(find.textContaining('250 kcal'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
      'IA→revisión/exclusión→borrador→Guardar→SQLite; no crea catálogo antes de Guardar',
      (tester) async {
    await loadTestFonts(tester);
    await tester.binding.setSurfaceSize(const Size(460, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = openInMemoryDatabase();
    await seedFoodsIfEmpty(db);
    final originalFoods = await db.select(db.foods).get();
    final host = DatabaseHost(
        File('unused.sqlite'), (_) => openInMemoryDatabase(),
        initial: db);
    final draft = MealDraft(date: DateTime(2026, 10, 9), slot: MealSlot.otro);
    const phrase = '250 g de arroz chino y Milo';
    var calls = 0;
    MockClient clientFactory() => MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          final task = body['task'] as String;
          if (task == 'status') {
            return _reply(task, {
              'enabled': true,
              'tasks': ['meal_text', 'meal_estimate']
            });
          }
          calls++;
          expect(task, 'meal_estimate');
          expect((body['input'] as Map)['text'], phrase);
          return _reply(
              task,
              estimateResult([
                estimateItem('Arroz chino'),
                estimateItem('Milo',
                    kind: 'unresolved', question: '¿Cuánto Milo?')
              ], [
                ('250 g de arroz chino', 0),
                (' y Milo', 1)
              ]));
        });
    await tester.pumpWidget(ProviderScope(
        overrides: [databaseHostProvider.overrideWithValue(host)],
        child: MaterialApp(
            home: MealFormScreen(
                draft: draft,
                textScreenBuilder: (foods) => MealTextScreen(
                    foods: foods,
                    activation: _Activation(),
                    clientFactory: clientFactory)))));
    final open = find.text('Describir comida · IA');
    // Tooltip/button label from the real parent, not a fabricated route.
    final textAction = find.text('Describir con IA');
    final action = textAction.evaluate().isNotEmpty
        ? textAction
        : find.textContaining('Describir');
    await tester.ensureVisible(action.first);
    await tester.tap(action.first);
    await tester.pumpAndSettle();
    expect(open, findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Describe la comida'), phrase);
    await tester.pump();
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
        .onChanged!(true);
    await tester.pump();
    await tester.ensureVisible(find.text('Preparar borrador'));
    await tester.tap(find.text('Preparar borrador'));
    await tester.pumpAndSettle();
    final vertical = find
        .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .last;
    await tester.scrollUntilVisible(find.text('¿Cuánto Milo?'), 400,
        scrollable: vertical);
    expect(calls, 1);
    expect(find.text('¿Cuánto Milo?'), findsOneWidget);
    final add = find.widgetWithText(FilledButton, 'Añadir al borrador');
    await tester.scrollUntilVisible(add, 400, scrollable: vertical);
    expect(tester.widget<FilledButton>(add).onPressed, isNull);
    final remember = find.byKey(const Key('estimate-remember-0'));
    await tester.scrollUntilVisible(remember, -350, scrollable: vertical);
    await tester.ensureVisible(remember);
    tester.widget<CheckboxListTile>(remember).onChanged!(true);
    await tester.pump();
    final confirm = find.byKey(const Key('estimate-confirm-0'));
    tester.widget<CheckboxListTile>(confirm).onChanged!(true);
    await tester.pump();
    final exclude = find.byKey(const Key('estimate-exclude-1'));
    await tester.scrollUntilVisible(exclude, 400, scrollable: vertical);
    await tester.pumpAndSettle();
    await tester.ensureVisible(exclude);
    await tester.tap(exclude);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Motivo: no lo comí, duplicado…'),
        'No lo comí; era otra bebida');
    await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
    await tester.pumpAndSettle();
    final coverage = find.byKey(const Key('estimate-coverage'));
    await tester.ensureVisible(coverage);
    tester.widget<CheckboxListTile>(coverage).onChanged!(true);
    await tester.pump();
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(draft.items.single.macros.kcal, 500);
    expect(draft.items.single.quantity, 250);
    await tester.tap(find.text('Arroz chino 250 g'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Guardar')));
    await tester.pumpAndSettle();
    expect(draft.items.single.quantity, 250);
    expect(draft.items.single.quantityUnit, 'g');
    expect(draft.items.single.macros.kcal, 500);
    expect(await db.select(db.meals).get(), isEmpty);
    expect(await db.select(db.foods).get(), originalFoods);
    final save = find.text('Guardar');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final meal = (await db.select(db.meals).get()).single;
    expect(meal.notes, contains(phrase));
    expect(meal.notes, contains('Receta y aceite desconocidos'));
    expect(meal.notes, contains('motivo: No lo comí'));
    expect(meal.notes, contains('gpt-6-luna'));
    final stored = (await db.select(db.mealItems).get()).single;
    expect(stored.quantity, 250);
    expect(stored.quantityUnit, 'g');
    expect(stored.kcal, 500);
    expect(stored.sourceVerified, isNull);
    final report = buildReport(
        await ReportRepository(db, NutritionRepository(db)).load(
            DateTime(2026, 10, 9), DateTime(2026, 10, 9),
            withPrevious: false));
    expect(report, contains(phrase));
    expect(report, contains('Receta y aceite desconocidos'));
    final learned = (await NutritionRepository(db).foodNamed('Arroz chino'))!;
    expect(learned.basis, FoodBasis.per100);
    expect(learned.kcal, 200);
    expect(learned.source, MacroSource.estimado);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    final closing = db.close();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await closing;
  });
  for (final failure in [false, true]) {
    testWidgets(
        failure
            ? 'fallo de red conserva frase y registro manual; cero escrituras'
            : 'volver con Recordar elegido no guarda comida ni catálogo',
        (tester) async {
      await loadTestFonts(tester);
      final db = openInMemoryDatabase();
      await seedFoodsIfEmpty(db);
      final before = await db.select(db.foods).get();
      final host = DatabaseHost(
          File('unused.sqlite'), (_) => openInMemoryDatabase(),
          initial: db);
      final draft = MealDraft(date: DateTime(2026, 10, 9), slot: MealSlot.otro);
      const phrase = '250 g de arroz chino';
      MockClient clientFactory() => MockClient((request) async {
            final body = jsonDecode(request.body) as Map;
            if (body['task'] == 'status') {
              return _reply('status', {
                'enabled': true,
                'tasks': ['meal_estimate']
              });
            }
            if (failure) return http.Response('private-provider-body', 500);
            return _reply('meal_estimate',
                estimateResult([estimateItem('Arroz chino')], [(phrase, 0)]));
          });
      await tester.pumpWidget(ProviderScope(
          overrides: [databaseHostProvider.overrideWithValue(host)],
          child: MaterialApp(
              home: MealFormScreen(
                  draft: draft,
                  textScreenBuilder: (foods) => MealTextScreen(
                      foods: foods,
                      activation: _Activation(),
                      clientFactory: clientFactory)))));
      await tester.ensureVisible(find.text('Describir comida · IA'));
      await tester.tap(find.text('Describir comida · IA'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Describe la comida'), phrase);
      await tester.pump();
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .onChanged!(true);
      await tester.pump();
      await tester.ensureVisible(find.text('Preparar borrador'));
      await tester.tap(find.text('Preparar borrador'));
      await tester.pumpAndSettle();
      if (failure) {
        expect(find.text('private-provider-body'), findsNothing);
        expect(
            tester
                .widget<TextField>(
                    find.widgetWithText(TextField, 'Describe la comida'))
                .controller!
                .text,
            phrase);
      } else {
        final remember = find.byKey(const Key('estimate-remember-0'));
        final vertical = find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .last;
        await tester.scrollUntilVisible(remember, 350, scrollable: vertical);
        tester.widget<CheckboxListTile>(remember).onChanged!(true);
        await tester.pump();
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(draft.items, isEmpty);
      expect(await db.select(db.meals).get(), isEmpty);
      expect(await db.select(db.foods).get(), before);
      expect(find.byTooltip('Entrada libre'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final closing = db.close();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await closing;
    });
  }
}
