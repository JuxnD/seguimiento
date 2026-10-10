import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:seguimiento/features/training/v3_timers.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/ui/progress_ring.dart';
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/domain/progress_metrics.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/features/body/test_results_screen.dart';
import 'package:seguimiento/features/report/report_screen.dart';
import 'package:seguimiento/features/report/charts_section.dart';
import 'package:seguimiento/features/report/charts.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/features/training/test_mode_screen.dart';
import 'package:seguimiento/ui/theme.dart';
import '../support/test_fonts.dart';
import '../support/radar_sql_fixture.dart';
import 'package:seguimiento/features/report/summary_screen.dart';
import 'package:seguimiento/features/report/personal_radar_widget.dart';
import '../support/sqlite_host.dart';

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

class _Today extends TodayNotifier {
  @override
  DateTime build() => DateTime(2026, 10, 10);
}

void main() {
  setUpAll(useHostSqlite);
  Future<void> tSetSurface(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(360,900));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester t, AppDatabase db) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 1));
    final closing = db.close();
    await t.pump(const Duration(seconds: 1));
    await closing;
  }

  Future<void> show(WidgetTester t, AppDatabase db,
      {double scale = 1, Widget home = const SummaryScreen(), ActiveSession? pending, DateTime Function()? decisionClock}) async {
    await loadTestFonts(t);
    final theme = buildGymTheme();
    await t.pumpWidget(ProviderScope(
        overrides: [
          databaseHostProvider
              .overrideWithValue(DatabaseHost(File('unused.sqlite'), (_) => openInMemoryDatabase(), initial: db)),
          todayProvider.overrideWith(_Today.new),
          decisionClockProvider.overrideWithValue(decisionClock ?? () => DateTime(2026, 10, 10, 12)),
          localFlagsProvider.overrideWithValue(LocalFlags(File('build/qa/011/no-flags.json'))),
          if (pending != null) activeSessionProvider.overrideWith((ref) async => pending),
          activeSessionStoreProvider.overrideWithValue(ActiveSessionStore(File('build/qa/011/no-active.json'))),
        ],
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
        appBarTheme: theme.appBarTheme.copyWith(titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(fontFamily:'Roboto')),
        segmentedButtonTheme: SegmentedButtonThemeData(style: theme.segmentedButtonTheme.style?.copyWith(textStyle:WidgetStateProperty.all(const TextStyle(fontFamily:'Roboto',fontWeight:FontWeight.w600,fontSize:13)))),
        inputDecorationTheme:theme.inputDecorationTheme.copyWith(labelStyle:const TextStyle(fontFamily:'Roboto'))),
            builder: (context, child) =>
                MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: RepaintBoundary(key: const Key('radar011-shot'), child: home))));
    await settle(t);
  }

  Future<void> shot(WidgetTester t, String name) async {
    final target = Platform.environment['RADAR_011_OUT'];
    if (target == null) return;
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(const Key('radar011-shot')));
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory(target)..createSync(recursive: true);
      File('${folder.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
      final radar = t.widget<PersonalRadarWidget>(find.byType(PersonalRadarWidget)).radar;
      File('${folder.path}/$name.json').writeAsStringSync(jsonEncode({
        'synthetic': true,
        'viewport': '360dp',
        'cutoff': radar.asOf.toIso8601String(),
        'axes': [
          for (final e in radar.axes)
            {
              'axis': e.axis.name,
              'unit': e.axis.unit,
              'first': e.firstEligible?.value,
              'current': e.current?.value,
              'firstDate': e.firstEligible?.date?.toIso8601String(),
              'currentDate': e.current?.date?.toIso8601String(),
              'referenceId': e.reference?.id,
              'reference': e.reference?.value,
              'referenceFrom': e.reference?.from.toIso8601String(),
              'observations': [
                for (final o in e.observations)
                  {'source': o.sourceKey, 'raw': o.raw, 'quality': o.quality, 'reason': o.reason}
              ],
            }
        ]
      }));
    });
  }

  Future<void> selectPull(WidgetTester t) async {
    await t.ensureVisible(find.byKey(const Key('radar-axis-pull')));
    await settle(t);
    await t.tap(find.byKey(const Key('radar-axis-pull')));
    await settle(t);
  }

  testWidgets('referencia guardar/cancelar SQLite, rutas abrir/cancelar sin resultados', (t) async {
    final db = openInMemoryDatabase();
    try {
      await seedRadarSql(db);
      await show(t, db);
      await selectPull(t);
      final edit = find.text('Revisar referencia de Tirón');
      await t.ensureVisible(edit);
      await settle(t);
      await t.tap(edit);
      await settle(t);
      final before = (await GoalRepository(db).history()).versions.length;
      await t.enterText(find.byKey(const Key('radar-reference-value')), '20');
      await t.tap(find.text('Cancelar'));
      await settle(t);
      expect((await GoalRepository(db).history()).versions.length, before);
      await t.tap(edit);
      await settle(t);
      await t.enterText(find.byKey(const Key('radar-reference-value')), '20');
      await t.tap(find.text('Guardar'));
      await settle(t);
      expect(
          (await GoalRepository(db).history()).current(GoalMetric.refDominadas, DateTime(2026, 10, 10))!.effectiveFrom,
          DateTime(2026, 10, 10));
      expect(t.widget<PersonalRadarWidget>(find.byType(PersonalRadarWidget)).radar.axis(RadarAxis.pull).currentPercent,
          40);
      final rows = (await db.select(db.fitnessTests).get()).length;
      final sessions = (await db.select(db.sessions).get()).length;
      await t.ensureVisible(find.text('Registrar Tirón'));
      await settle(t);
      await t.tap(find.text('Registrar Tirón'));
      await settle(t);
      expect(find.byType(TestResultsScreen), findsOneWidget);
      expect(find.textContaining('16–22 nov'), findsNothing);
      await t.tap(find.text('T3 torso'));
      await settle(t);
      expect(find.byType(TestModeScreen), findsOneWidget);
      expect(dateOnly(t.widget<TestModeScreen>(find.byType(TestModeScreen)).date), dateOnly(DateTime.now()));
      await t.pageBack();
      await settle(t);
      await t.pageBack();
      await settle(t);
      expect((await db.select(db.fitnessTests).get()).length, rows);
      expect((await db.select(db.sessions).get()).length, sessions);
      expect(t.takeException(), isNull);
    } finally {
      await close(t, db);
    }
  });
  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets('SQL→Tu progreso viewport inicial360 texto$scale y detalle', (t) async {
      await t.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final db = openInMemoryDatabase();
      try {
        await seedRadarSql(db);
        await show(t, db, scale: scale);
        expect(find.text('Tus capacidades'), findsOneWidget);
        final radar = t.widget<PersonalRadarWidget>(find.byType(PersonalRadarWidget)).radar;
        expect(radar.axes.where((e) => e.currentPercent != null).length, 6);
        // Initial screenshot without scroll or ensureVisible: proves hierarchy.
        await shot(t, 'seis-inicial-360-texto$scale');
        expect(t.takeException(), isNull);
        await selectPull(t);
        await t.ensureVisible(find.text('Evidencia de Tirón'));
        await settle(t);
        await shot(t, 'seis-detalle-360-texto$scale');
        expect(find.textContaining('Última apta: 8 reps'), findsOneWidget);
        expect(find.textContaining('Referencia común: 10 reps'), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        await close(t, db);
      }
    });
  }
  testWidgets('dos ejes/sin referencia y pasado no cambia por decisión de hoy', (t) async {
    final db = openInMemoryDatabase();
    try {
      await seedRadarSql(db, complete: false, references: false);
      await (db.update(db.profiles)..where((p) => p.id.equals(1)))
          .write(const ProfilesCompanion(startDate: Value('2026-01-01')));
      await show(t, db);
      await shot(t, 'dos-sin-referencia');
      await t.scrollUntilVisible(find.byTooltip('Anterior'), 250, scrollable: find.byType(Scrollable).first);
      await settle(t);
      await t.tap(find.byTooltip('Anterior'));
      await settle(t);
      await selectPull(t);
      await t.ensureVisible(find.text('Definir referencia de Tirón'));
      await settle(t);
      await t.tap(find.text('Definir referencia de Tirón'));
      await settle(t);
      expect(find.textContaining('este cambio no lo modifica'), findsOneWidget);
      await t.enterText(find.byKey(const Key('radar-reference-value')), '10');
      await t.tap(find.text('Guardar'));
      await settle(t);
      expect(
          t.widget<PersonalRadarWidget>(find.byType(PersonalRadarWidget)).radar.axis(RadarAxis.pull).reference, isNull);
      expect(
          (await GoalRepository(db).history()).current(GoalMetric.refDominadas, DateTime(2026, 10, 10))!.effectiveFrom,
          DateTime(2026, 10, 10));
      expect(t.takeException(), isNull);
    } finally {
      await close(t, db);
    }
  });
  testWidgets('Cindy cancelada conserva pendiente y no crea sesión nueva', (t) async {
    final db = openInMemoryDatabase();
    try {
      final pending =
          CounterSnapshot(date: '2026-10-09', startedAt: DateTime(2026, 10, 9, 12), phase: CounterPhase.circuit);
      await show(t, db, pending: pending);
      final axis = find.byKey(const Key('radar-axis-circuit'));
      await t.ensureVisible(axis);
      await settle(t);
      await t.tap(axis);
      await settle(t);
      await t.ensureVisible(find.text('Registrar Circuito'));
      await settle(t);
      await t.tap(find.text('Registrar Circuito'));
      await settle(t);
      await t.tap(find.text('Cancelar'));
      await settle(t);
      expect((await db.select(db.sessions).get()), isEmpty);
      await t.tap(find.text('Registrar Circuito'));
      await settle(t);
      await t.tap(find.text('Abrir prueba'));
      await settle(t);
      expect(find.text('Hay una sesión sin terminar'), findsOneWidget);
      final context = t.element(find.byType(SummaryScreen));
      final container = ProviderScope.containerOf(context);
      expect((await container.read(activeSessionProvider.future)), same(pending));
      await t.tapAt(const Offset(8, 8));
      await settle(t);
      expect((await db.select(db.sessions).get()), isEmpty);
      expect((await container.read(activeSessionProvider.future)), same(pending));
      expect(t.takeException(), isNull);
    } finally {
      await close(t, db);
    }
  });
  testWidgets('pasos ausentes≠0 y adaptador proteína histórica por día', (t) async {
    final db = openInMemoryDatabase();
    try {
      await (db.update(db.profiles)..where((p) => p.id.equals(1)))
          .write(const ProfilesCompanion(startDate: Value('2026-10-05')));
      await db.into(db.dailySteps).insert(DailyStepsCompanion.insert(date: '2026-10-05', steps: 0));
      final goals = GoalRepository(db);
      await (db.delete(db.goalVersions)..where((v) => v.metric.equals('proteinaMin') | v.metric.equals('pasos'))).go();
      await goals.scheduleGoal(GoalMetric.pasos, 5000, effectiveFrom: DateTime(2026, 10, 5), origin: GoalOrigin.perfil);
      await goals.scheduleGoal(GoalMetric.proteinaMin, 130,
          effectiveFrom: DateTime(2026, 10, 5), origin: GoalOrigin.perfil);
      await goals.scheduleGoal(GoalMetric.proteinaMin, 160,
          effectiveFrom: DateTime(2026, 10, 9), origin: GoalOrigin.perfil);
      await show(t, db);
      await t.scrollUntilVisible(find.text('Pasos'), 300, scrollable: find.byType(Scrollable).first);
      await settle(t);
      final chart = t.widget<DailyBarsChart>(find.byType(DailyBarsChart));
      expect(chart.metric, 'steps');
      expect(chart.goal, isNull);
      expect(chart.days!.first.value, 0);
      expect(chart.days![1].value, isNull);
      expect(chart.goalResolver!(DateTime(2026, 10, 5), 'steps')!.value, 5000);
      expect(chart.goalResolver!(DateTime(2026, 10, 10), 'steps'), isNull);
      expect(chart.days!.where((d) => d.value != null).length, 1);
      await show(t, db, home: const ReportScreen());
      await t.scrollUntilVisible(find.byType(ChartsSection), 300, scrollable: find.byType(Scrollable).first);
      await settle(t);
      final section = t.widget<ChartsSection>(find.byType(ChartsSection));
      final old = section.goalResolver!(DateTime(2026, 10, 6), 'proteinMin')!;
      final current = section.goalResolver!(DateTime(2026, 10, 9), 'proteinMin')!;
      expect((old.value, old.to), (130, DateTime(2026, 10, 8)));
      expect((current.value, current.to), (160, null));
      expect(section.goalResolver!(DateTime(2026, 10, 4), 'proteinMin'), isNull);
      expect(current.covers(DateTime(2026, 11, 30)), isTrue);
      expect(t.takeException(), isNull);
    } finally {
      await close(t, db);
    }
  });
  testWidgets('Cindy abre cronómetro real con checklist y cancelar no escribe SQLite', (t) async {
    final db=openInMemoryDatabase();
    try {
      wakelock.wakelockPlusPlatformInstance=_NoWakelock();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (_) async=>null);
      await show(t,db);
      final axis=find.byKey(const Key('radar-axis-circuit'));
      await t.ensureVisible(axis);await settle(t);await t.tap(axis);await settle(t);
      await t.ensureVisible(find.text('Registrar Circuito'));await settle(t);await t.tap(find.text('Registrar Circuito'));await settle(t);
      await t.tap(find.text('Abrir prueba'));await settle(t);
      expect(find.byType(AmrapScreen),findsOneWidget);
      expect(t.widget<AmrapScreen>(find.byType(AmrapScreen)).attempt,isTrue);
      expect((await db.select(db.sessions).get()),isEmpty);
      await t.pageBack();await settle(t);
      expect((await db.select(db.sessions).get()),isEmpty);
      expect(t.takeException(),isNull);
    } finally {await close(t,db);}
  });
  testWidgets('anillo proteína variable muestra días1/2 y kcal conserva promedio', (t) async {
    await t.binding.setSurfaceSize(const Size(360,900)); addTearDown(() => t.binding.setSurfaceSize(null));
    final db=openInMemoryDatabase();
    try {
      await (db.update(db.profiles)..where((p)=>p.id.equals(1))).write(const ProfilesCompanion(startDate:Value('2026-10-05')));
      await (db.delete(db.goalVersions)..where((v)=>v.metric.equals('proteinaMin') | v.metric.equals('kcal') | v.metric.equals('kcalFutbol'))).go();
      final goals=GoalRepository(db);
      await goals.scheduleGoal(GoalMetric.proteinaMin,130,effectiveFrom:DateTime(2026,10,5),origin:GoalOrigin.perfil);
      await goals.scheduleGoal(GoalMetric.proteinaMin,160,effectiveFrom:DateTime(2026,10,10),origin:GoalOrigin.perfil);
      await goals.scheduleGoal(GoalMetric.kcal,2400,effectiveFrom:DateTime(2026,10,5),origin:GoalOrigin.perfil);
      await goals.scheduleGoal(GoalMetric.kcalFutbol,2800,effectiveFrom:DateTime(2026,10,5),origin:GoalOrigin.perfil);
      final nutrition=NutritionRepository(db);
      for (final day in [DateTime(2026,10,9),DateTime(2026,10,10)]) {
        await nutrition.saveMeal(MealDraft(date:day,slot:MealSlot.desayuno,items:[MealItemDraft(label:'FICTICIO',quantity:1,quantityUnit:'porción',macros:const Macros(kcal:2400,protein:140))]));
        await nutrition.setClosed(day,true);
      }
      await show(t,db,scale:2);
      await t.scrollUntilVisible(find.text('Comida'),300,scrollable:find.byType(Scrollable).first);await settle(t);
      final rings=t.widgetList<ProgressRing>(find.byType(ProgressRing)).toList();
      expect(rings.where((r)=>r.label=='kcal/día'),isEmpty);
      final protein=rings.singleWhere((r)=>r.label=='Días que alcanzaron mínimo');
      expect((protein.progress,protein.value),(0.5,'1/2'));
      expect(protein.sublabel,'Promedio 140 g/día');
      expect(find.text('Promedio kcal/día'),findsOneWidget);
      expect(find.textContaining('Referencias kcal: 2.400'),findsOneWidget);
      expect(find.textContaining('2.800'),findsOneWidget);
      expect(t.takeException(),isNull);
    } finally {await close(t,db);}
  });
  testWidgets('referencia confirma día real al cruzar medianoche sin backdate', (t) async {
    final db=openInMemoryDatabase();
    try {
      var now=DateTime(2026,10,10,23,59);
      await show(t,db,decisionClock:()=>now);
      await selectPull(t);
      await t.ensureVisible(find.text('Definir referencia de Tirón'));await settle(t);await t.tap(find.text('Definir referencia de Tirón'));await settle(t);
      await t.enterText(find.byKey(const Key('radar-reference-value')),'10');
      now=DateTime(2026,10,11,0,1);
      await t.tap(find.text('Guardar'));await settle(t);
      final row=(await GoalRepository(db).history()).versions.where((v)=>v.metric==GoalMetric.refDominadas).single;
      expect((row.effectiveFrom,row.acceptedAt),(DateTime(2026,10,11),DateTime(2026,10,11)));
      expect(t.widget<PersonalRadarWidget>(find.byType(PersonalRadarWidget)).radar.axis(RadarAxis.pull).reference,isNull);
      expect(t.takeException(),isNull);
    }finally{await close(t,db);}
  });
  testWidgets('Tu progreso conecta radar real incluso sin pruebas', (tester) async {
    final db = openInMemoryDatabase();
    try {
      await tSetSurface(tester);
      await show(tester, db);
      await shot(tester,'sin-registros-inicial');
      expect(find.byType(PersonalRadarWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      final closing = db.close();
      await tester.pump(const Duration(seconds: 1));
      await closing;
    }
  });
}
