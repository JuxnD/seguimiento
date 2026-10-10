import 'dart:io';
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/domain/progress.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/chart_evidence.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/chart_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/ui/theme.dart';
import 'package:seguimiento/ui/widgets.dart';
import 'package:seguimiento/features/report/charts.dart';
import 'package:seguimiento/features/report/charts_section.dart';
import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

void main() {
  setUpAll(useHostSqlite);
  Future<void> closeDb(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    final closing = db.close();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await closing;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final target = Platform.environment['CHARTS_015_OUT'];
    if (target == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('charts-shot')));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory(target)..createSync(recursive: true);
      File('${folder.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
      'registro antiguo fuera de ventanas90/60 se actualiza en rango activo',
      (tester) async {
    final db = openInMemoryDatabase();
    try {
      final weight = await db
          .into(db.bodyWeights)
          .insert(BodyWeightsCompanion.insert(date: '2026-01-01', kg: 70));
      final session = await db.into(db.sessions).insert(
          SessionsCompanion.insert(
              date: '2026-01-01',
              type: SessionType.circuito,
              roundsDone: const Value(3)));
      await db.transaction(() async {
        for (var i = 0; i < 100; i++) {
          final day = dayKey(DateTime(2026, 2, i + 1));
          await db
              .into(db.bodyWeights)
              .insert(BodyWeightsCompanion.insert(date: day, kg: 80));
          await db.into(db.sessions).insert(SessionsCompanion.insert(
              date: day,
              type: SessionType.circuito,
              roundsDone: const Value(5)));
        }
      });
      final host = DatabaseHost(
          File('unused.sqlite'), (_) => openInMemoryDatabase(),
          initial: db);
      await tester.pumpWidget(ProviderScope(
          overrides: [databaseHostProvider.overrideWithValue(host)],
          child: const MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: ChartsSection(
                          range: ('2026-01-01', '2026-01-02')))))));
      await settle(tester);
      TrendChart chart(String unit) => tester
          .widgetList<TrendChart>(find.byType(TrendChart))
          .where((w) => w.unit == unit)
          .single;
      expect(chart('kg').points.single.value, 70);
      expect(chart('rondas').points.single.value, 3);
      await (db.update(db.bodyWeights)..where((w) => w.id.equals(weight)))
          .write(const BodyWeightsCompanion(kg: Value(71)));
      await (db.update(db.sessions)..where((s) => s.id.equals(session)))
          .write(const SessionsCompanion(roundsDone: Value(4)));
      await settle(tester);
      expect(chart('kg').points.single.value, 71);
      expect(chart('rondas').points.single.value, 4);
      expect(tester.takeException(), isNull);
    } finally {
      await closeDb(tester, db);
    }
  });

  testWidgets(
      'único cero cerrado tiene eje positivo; todas ausentes no dibujan cifra',
      (tester) async {
    await loadTestFonts(tester);
    final day = DateTime(2026, 10, 2);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DailyBarsChart(
                points: [SeriesPoint(day, 0)],
                days: [ChartDay(day, 0, ChartDayStatus.closed)],
                color: Colors.blue,
                unit: 'g'))));
    await settle(tester);
    final data = tester.widget<BarChart>(find.byType(BarChart)).data;
    expect(data.maxY, greaterThan(0));
    expect(data.barGroups.single.barRods.single.toY, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DailyBarsChart(
                points: const [],
                days: [ChartDay(day, null, ChartDayStatus.missing)],
                color: Colors.blue,
                unit: 'g'))));
    await settle(tester);
    expect(find.byType(BarChart), findsNothing);
    expect(find.text('Sin comidas registradas en el rango.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('selector explica dosis/carga/ventana20vs30 antes de escoger',
      (tester) async {
    await loadTestFonts(tester);
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = openInMemoryDatabase();
    try {
      final exercises = ExerciseRepository(db),
          plan = PlanRepository(db, ExerciseRepository(db));
      await seedIfEmpty(db, plan);
      final pd = (await plan.dayFor(DateTime(2026, 10, 1)))!.dayId;
      final training = TrainingRepository(db, exercises);
      for (final (day, span, rounds) in [(1, 1200, 8), (2, 1800, 12)]) {
        await training.save(SessionDraft(
            date: DateTime(2026, 10, day),
            planDayId: pd,
            type: SessionType.resistencia,
            mode: 'cindy',
            totalSec: span,
            roundsDone: rounds,
            sets: [
              SetDraft(
                  exercise: 'Flexiones',
                  reps: 10,
                  variant: 'cerradas',
                  loadKg: 5)
            ]));
      }
      final points = await ChartRepository(db, NutritionRepository(db))
          .rounds(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 2));
      await tester.pumpWidget(RepaintBoundary(
          key: const Key('charts-shot'),
          child: MaterialApp(
              theme: buildGymTheme().copyWith(
                  textTheme:
                      buildGymTheme().textTheme.apply(fontFamily: 'Roboto'),
                  inputDecorationTheme: buildGymTheme()
                      .inputDecorationTheme
                      .copyWith(
                          labelStyle: buildGymTheme()
                              .inputDecorationTheme
                              .labelStyle
                              ?.copyWith(fontFamily: 'Roboto'))),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.6)),
                  child: child!),
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: AppCard(title: 'Rondas por sesión', children: [
                EvidenceSeries(
                    points: points,
                    color: Colors.orange,
                    unit: 'rondas',
                    integer: true)
              ]))))));
      await settle(tester);
      final dropdown = tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
      final descriptions =
          dropdown.items!.map((i) => (i.child as Text).data!).toList();
      expect(descriptions[0], contains('20 min'));
      expect(descriptions[1], contains('30 min'));
      expect(
          descriptions.every((s) =>
              s.contains('Flexiones') &&
              s.contains('10 reps') &&
              s.contains('cerradas') &&
              s.contains('5 kg')),
          isTrue);
      await tester.tap(find.byType(DropdownButton<String>));
      await settle(tester);
      await shot(tester, 'selector-360-texto16');
      await tester.tap(find.textContaining('30 min').last);
      await settle(tester);
      final chart = tester.widget<TrendChart>(find.byType(TrendChart));
      expect(chart.points.single.value, 12);
      await tester.ensureVisible(find.text('Ver registros y evidencia'));
      await tester.tap(find.text('Ver registros y evidencia'));
      await settle(tester);
      expect(find.widgetWithText(ListTile, '2 oct 2026 · 12 rondas'),
          findsOneWidget);
      expect(
          find.widgetWithText(ListTile, '1 oct 2026 · 8 rondas'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await closeDb(tester, db);
    }
  });

  testWidgets(
      'barras: ausencia sin rod,0 observado, meta sólo en fecha documentada',
      (tester) async {
    final days = [
      ChartDay(DateTime(2026, 10, 1), null, ChartDayStatus.missing),
      ChartDay(DateTime(2026, 10, 2), 0, ChartDayStatus.closed),
      ChartDay(DateTime(2026, 10, 3), 20, ChartDayStatus.incomplete)
    ];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DailyBarsChart(
                points: [
          SeriesPoint(days[1].date, 0),
          SeriesPoint(days[2].date, 20)
        ],
                days: days,
                color: Colors.blue,
                unit: 'g',
                goalResolver: (date, metric) => DatedChartGoal(
                    from: days[2].date,
                    to: days[2].date,
                    value: 130,
                    unit: 'g',
                    source: 'Fixture objetivo explícito')))));
    final data = tester.widget<BarChart>(find.byType(BarChart)).data;
    expect(data.barGroups.map((g) => g.barRods.length), [0, 1, 2]);
    expect(data.barGroups[1].barRods.single.toY, 0);
    expect(data.barGroups[2].barRods.last.toY, 130);
    expect(data.extraLinesData.horizontalLines, isEmpty);
    final tooltip = data.barTouchData.touchTooltipData.getTooltipItem(
        data.barGroups[1], 1, data.barGroups[1].barRods.first, 0)!;
    expect(tooltip.text, contains('Día cerrado'));
    expect(tooltip.text, contains('2 oct 2026'));
  });
  testWidgets(
      'SQLite→rango/tipo/tabla/evidencia y cierre reactivo a360 con texto1.6',
      (tester) async {
    await loadTestFonts(tester);
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = openInMemoryDatabase();
    var cleaned = false;
    Future<void> cleanup() async {
      if (cleaned) return;
      cleaned = true;
      await closeDb(tester, db);
    }

    addTearDown(cleanup);
    final exercises = ExerciseRepository(db),
        plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    final pd = (await plan.dayFor(DateTime(2026, 10, 6)))!.dayId;
    final training = TrainingRepository(db, exercises);
    for (final (day, rounds, type) in [
      (6, 6, SessionType.circuito),
      (7, 7, SessionType.circuito),
      (8, 9, SessionType.progresion),
      (9, 8, SessionType.circuito)
    ]) {
      await training.save(SessionDraft(
          date: DateTime(2026, 10, day),
          planDayId: pd,
          type: type,
          roundsDone: rounds,
          sets: [SetDraft(exercise: 'Flexiones', reps: 10)]));
    }
    for (final (date, site, value) in [
      ('2026-09-01', MeasureSite.pecho, 95.0),
      ('2026-10-09', MeasureSite.abdomen, 90.0)
    ]) {
      await db.into(db.measurements).insert(
          MeasurementsCompanion.insert(date: date, site: site, valueCm: value));
    }
    for (final date in ['2026-09-01', '2026-10-09']) {
      await db.into(db.bodyWeights).insert(BodyWeightsCompanion.insert(
          date: date, kg: 70, fasted: const Value(true)));
    }
    final meal = await db
        .into(db.meals)
        .insert(MealsCompanion.insert(date: '2026-10-06', slot: MealSlot.otro));
    await db.into(db.mealItems).insert(MealItemsCompanion.insert(
        mealId: meal, label: 'Fixture', kcal: 500, protein: 50));
    final host = DatabaseHost(
        File('unused.sqlite'), (_) => openInMemoryDatabase(),
        initial: db);
    var range = ('2026-10-05', '2026-10-10');
    late StateSetter changeRange;
    await tester.pumpWidget(ProviderScope(
        overrides: [databaseHostProvider.overrideWithValue(host)],
        child: MaterialApp(
            theme: buildGymTheme().copyWith(
                textTheme:
                    buildGymTheme().textTheme.apply(fontFamily: 'Roboto'),
                appBarTheme: buildGymTheme().appBarTheme.copyWith(
                    titleTextStyle: buildGymTheme()
                        .appBarTheme
                        .titleTextStyle
                        ?.copyWith(fontFamily: 'Roboto')),
                chipTheme: buildGymTheme().chipTheme.copyWith(
                    labelStyle: buildGymTheme()
                        .chipTheme
                        .labelStyle
                        ?.copyWith(fontFamily: 'Roboto')),
                inputDecorationTheme:
                    buildGymTheme()
                        .inputDecorationTheme
                        .copyWith(
                            labelStyle: buildGymTheme()
                                .inputDecorationTheme
                                .labelStyle
                                ?.copyWith(fontFamily: 'Roboto'))),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!),
            home: RepaintBoundary(
                key: const Key('charts-shot'),
                child: Scaffold(
                    appBar: AppBar(title: const Text('Informe')),
                    body: StatefulBuilder(builder: (context, setState) {
                      changeRange = setState;
                      return SingleChildScrollView(
                          child: ChartsSection(range: range));
                    }))))));
    await settle(tester);
    expect(find.textContaining('Gráficas: 5 oct 2026'), findsOneWidget);
    var chart = tester
        .widgetList<TrendChart>(find.byType(TrendChart))
        .where((w) => w.unit == 'rondas')
        .single;
    expect(chart.points.map((p) => p.value), [6, 7, 8]);
    expect(find.textContaining('De 6 a 8 rondas'), findsOneWidget);
    await shot(tester, 'rondas-360-texto16');
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Progresión'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Progresión'));
    await settle(tester);
    chart = tester
        .widgetList<TrendChart>(find.byType(TrendChart))
        .where((w) => w.unit == 'rondas')
        .single;
    expect(chart.points.single.value, 9);
    expect(find.textContaining('De 6 a 8 rondas'), findsNothing);
    await tester.ensureVisible(find.text('Ver registros y evidencia').first);
    await tester.tap(find.text('Ver registros y evidencia').first);
    await settle(tester);
    final tile = find.widgetWithText(ListTile, '8 oct 2026 · 9 rondas');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await settle(tester);
    expect(find.textContaining('Registro seleccionado: 8 oct 2026'),
        findsOneWidget);
    final dayTable = find.text('Ver días y evidencia');
    await tester.ensureVisible(dayTable);
    await tester.tap(dayTable);
    await settle(tester);
    expect(
        find.textContaining('5 oct 2026 · — · Sin registro'), findsOneWidget);
    expect(find.textContaining('6 oct 2026 · 50 g · Registro incompleto'),
        findsOneWidget);
    await NutritionRepository(db).setClosed(DateTime(2026, 10, 6), true);
    await settle(tester);
    final provider =
        ProviderScope.containerOf(tester.element(find.byType(ChartsSection)));
    final refreshed = await provider.read(proteinSeriesProvider(range).future);
    expect(refreshed.singleWhere((d) => d.date.day == 6).status,
        ChartDayStatus.closed);
    expect(
        find.textContaining('6 oct 2026 · 50 g · Día cerrado'), findsOneWidget);
    expect(find.textContaining('Meta histórica no disponible'), findsOneWidget);
    await tester.ensureVisible(find.text('Proteína por día · g'));
    await settle(tester);
    await shot(tester, 'proteina-360-texto16');
    changeRange(() => range = ('2026-09-01', '2026-09-02'));
    await settle(tester);
    expect(find.textContaining('Gráficas: 1 sep 2026'), findsOneWidget);
    expect(find.textContaining('De 6 a 8 rondas'), findsNothing);
    expect(
        tester
            .widgetList<TrendChart>(find.byType(TrendChart))
            .where((w) => w.unit == 'kg')
            .single
            .points
            .single
            .date
            .month,
        9);
    expect(find.text('Medidas · Pecho'), findsOneWidget);
    expect(find.text('Medidas · Abdomen (ombligo)'), findsNothing);
    expect(tester.takeException(), isNull);
    await cleanup();
  });
  testWidgets('X distingue un día de un mes, sin suavizado artificial',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TrendChart(points: [
      SeriesPoint(DateTime(2026, 1, 1), 3),
      SeriesPoint(DateTime(2026, 1, 2), 4),
      SeriesPoint(DateTime(2026, 2, 1), 5)
    ], color: Colors.orange))));
    final line = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData
        .single;
    expect(line.spots.map((s) => s.x), [0, 1, 31]);
    expect(line.isCurved, isFalse);
  });
  testWidgets('rango de informe filtra peso real, incluida una toma sola',
      (tester) async {
    await loadTestFonts(tester);
    final db = openInMemoryDatabase();
    for (final day in ['2026-09-01', '2026-10-01', '2026-10-09']) {
      await db
          .into(db.bodyWeights)
          .insert(BodyWeightsCompanion.insert(date: day, kg: 70));
    }
    final host = DatabaseHost(
        File('unused.sqlite'), (_) => openInMemoryDatabase(),
        initial: db);
    await tester.pumpWidget(ProviderScope(
        overrides: [databaseHostProvider.overrideWithValue(host)],
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child:
                        ChartsSection(range: ('2026-10-05', '2026-10-10')))))));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final chart = tester
        .widgetList<TrendChart>(find.byType(TrendChart))
        .where((w) => w.unit == 'kg')
        .single;
    expect(chart.points.map((p) => p.date.day), [9]);
    await tester.pumpWidget(const SizedBox.shrink());
    final closing = db.close();
    await tester.pump(const Duration(seconds: 1));
    await closing;
  });
}
