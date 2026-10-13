import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/sleep_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/recovery.dart' show WeighMoment;
import 'package:seguimiento/features/home/home_screen.dart';
import 'package:seguimiento/features/settings/custom_reminders.dart';
import 'package:seguimiento/features/training/football_form_screen.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/sqlite_host.dart';

/// Plan 040 en pantalla. Estas tres pruebas compilan contra la base 25
/// (85f92c6) y fallan ahí por el comportamiento, no por API: tocar el sueño lo
/// borraba, el partido nuevo copiaba los pesajes del día y el pendiente no
/// decía de dónde salió ni se podía quitar desde Hoy. Fechas ficticias.
class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2030, 3, 4);
}

void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2030, 3, 4);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('seguimiento_040'));

  /// Como 032/033: la operación empieza en la zona de la pantalla y se
  /// avanzan las dos zonas por turnos; con tope, falla en vez de colgarse.
  Future<T> drive<T>(WidgetTester tester, Future<T> Function() op) async {
    T? value;
    Object? error;
    var done = false;
    unawaited(op().then((v) {
      value = v;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    }));
    for (var i = 0; i < 200 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    if (!done) fail('operación con la base sin terminar tras 200 turnos');
    if (error != null) throw error!;
    return value as T;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
  }

  List<Override> base(AppDatabase db) => [
        databaseProvider.overrideWithValue(db),
        localFlagsProvider.overrideWithValue(LocalFlags(File('${dir.path}/flags.json'))),
        todayProvider.overrideWith(_FixedToday.new),
      ];

  Future<void> mount(WidgetTester tester, List<Override> overrides, Widget home) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildGymTheme(), home: home),
    ));
    await settle(tester);
  }

  Future<void> close(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await drive(tester, db.close);
  }

  TodayDashboard dashboard() => TodayDashboard(
        date: mon,
        weekIndex: 1,
        dayType: DayType.descanso,
        planVersion: 3,
        planSummary: null,
        mainExercises: const [],
        blockExercises: const [],
        targetRounds: null,
        roundsDone: null,
        sessionsToday: 0,
        streak: 0,
        macros: const Macros(),
        proteinMin: 130,
        proteinMax: 160,
        kcalTarget: 2400,
        roundsRecord: null,
        measurement: null,
      );

  testWidgets('sueño anotado en Hoy: tocarlo abre la edición y no lo borra', (tester) async {
    final db = openInMemoryDatabase();
    await drive(tester, () => SleepRepository(db).set(mon, 8));
    await mount(
        tester,
        [
          ...base(db),
          dashboardProvider.overrideWith((ref) => dashboard()),
          activeSessionProvider.overrideWith((ref) => null),
          updateCheckProvider.overrideWith((ref) => const UpdateCheck(currentVersion: '1.23.0')),
          morningDoneProvider.overrideWith((ref, _) => true),
        ],
        const HomeScreen());
    final line = find.textContaining('Anoche: 8 h en cama');
    await tester.scrollUntilVisible(line, 120, scrollable: find.byType(Scrollable).first);
    await tester.tap(line);
    await settle(tester);
    expect(find.text('Sueño de anoche'), findsOneWidget, reason: 'abre la edición');
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    final rows = await drive(tester, () => db.select(db.sleepLogs).get());
    expect(rows.map((r) => r.hours), [8], reason: 'tocar ya no borra; cancelar no escribe');
    await drive(tester, db.close);
  });

  testWidgets('partido nuevo: no toma los pesajes del día sin confirmar', (tester) async {
    final db = openInMemoryDatabase();
    await drive(tester, () async {
      await BodyRepository(db).addWeight(mon, 80.5, moment: WeighMoment.antesFutbol);
      await BodyRepository(db).addWeight(mon, 79.3, moment: WeighMoment.despuesFutbol);
    });
    await mount(tester, base(db), FootballFormScreen(date: mon));
    final fields = tester.widgetList<TextField>(find.byType(TextField)).map((f) => f.controller?.text ?? '').toList();
    expect(fields, isNot(contains('80,5')), reason: 'antes se copiaba sin saber si era de este partido');
    expect(fields, isNot(contains('79,3')));
    expect(find.textContaining('¿Son de este partido?'), findsOneWidget);
    await close(tester, db);
  });

  testWidgets('pendiente de antes: dice "origen sin registrar" y quitar afecta sólo a ese', (tester) async {
    final db = openInMemoryDatabase();
    await drive(
        tester,
        () => db.customStatement('insert into custom_reminders (title, interval_days, hour, minute, start_date, enabled) '
            "values ('Ejercicio de prueba', 1, 8, 0, '2030-03-01', 1), ('Otro pendiente', 1, 8, 0, '2030-03-01', 1)"));
    await mount(tester, base(db), const Scaffold(body: SingleChildScrollView(child: TodayCustomRemindersCard())));
    expect(find.text('Ejercicio de prueba'), findsOneWidget);
    expect(find.textContaining('Origen sin registrar'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(TextButton, 'Quitar').first);
    await settle(tester);
    expect(find.text('¿Quitar "Ejercicio de prueba"?'), findsOneWidget, reason: 'confirma el elemento exacto');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Quitar')));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    final left = await drive(tester, () => db.select(db.customReminders).get());
    expect(left.map((r) => r.title), ['Otro pendiente']);
    await drive(tester, db.close);
  });
}
