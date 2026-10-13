import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
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
import 'package:seguimiento/domain/sleep_entry.dart';
import 'package:seguimiento/features/home/home_screen.dart';
import 'package:seguimiento/features/settings/custom_reminders.dart';
import 'package:seguimiento/features/training/football_form_screen.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/sqlite_host.dart';

/// Plan 040: los flujos completos sobre SQLite real. Fechas ficticias.
class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2030, 3, 4);
}

void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2030, 3, 4);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('seguimiento_040_flows'));

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

  /// 10 × 30 ms: deja terminar la animación de cierre de un diálogo (150 ms).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
  }

  List<Override> base(AppDatabase db) => [
        databaseProvider.overrideWithValue(db),
        localFlagsProvider.overrideWithValue(LocalFlags(File('${dir.path}/flags.json'))),
        todayProvider.overrideWith(_FixedToday.new),
      ];

  Future<void> mount(WidgetTester tester, List<Override> overrides, Widget home) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(theme: buildGymTheme(), home: home)));
    await settle(tester);
  }

  /// Abre `screen` encima de una pantalla base: guardar hace pop.
  Future<void> mountPushed(WidgetTester tester, List<Override> overrides, Widget screen) async {
    await mount(
        tester,
        overrides,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute<bool>(builder: (_) => screen)),
              child: const Text('abrir'),
            ),
          ),
        ));
    await tester.tap(find.text('abrir'));
    await settle(tester);
  }

  /// Desmonta y lee la base fuera de la pantalla.
  Future<T> read<T>(WidgetTester tester, Future<T> Function() op) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    return drive(tester, op);
  }

  Finder inDialog(String text) => find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  List<Override> home(AppDatabase db) => [
        ...base(db),
        dashboardProvider.overrideWith((ref) => TodayDashboard(
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
            )),
        activeSessionProvider.overrideWith((ref) => null),
        updateCheckProvider.overrideWith((ref) => const UpdateCheck(currentVersion: '1.23.0')),
        morningDoneProvider.overrideWith((ref, _) => true),
      ];

  Future<void> tapSleep(WidgetTester tester) async {
    final line = find.textContaining('Anoche:');
    await tester.scrollUntilVisible(line, 120, scrollable: find.byType(Scrollable).first);
    await tester.tap(line);
    await settle(tester);
  }

  testWidgets('sueño: editar horas guarda como manual; eliminar pide confirmación', (tester) async {
    final db = openInMemoryDatabase();
    await drive(tester, () => SleepRepository(db).set(mon, 8));
    await mount(tester, home(db), const HomeScreen());
    await tapSleep(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Horas en cama'), '7:30');
    await tester.tap(inDialog('Guardar'));
    await settle(tester);
    var d = (await read(tester, () => SleepRepository(db).detail(mon)))!;
    expect((d.hours, d.source), (7.5, sleepSourceManual));

    await mount(tester, home(db), const HomeScreen());
    await tapSleep(tester);
    await tester.tap(inDialog('Eliminar'));
    await settle(tester);
    expect(find.text('¿Eliminar el sueño de anoche?'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Cancelar')));
    await settle(tester);
    d = (await read(tester, () => SleepRepository(db).detail(mon)))!;
    expect(d.hours, 7.5, reason: 'cancelar la confirmación no borra');

    await mount(tester, home(db), const HomeScreen());
    await tapSleep(tester);
    await tester.tap(inDialog('Eliminar'));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Eliminar')));
    await settle(tester);
    expect(await read(tester, () => SleepRepository(db).detail(mon)), isNull);
    await drive(tester, db.close);
  });

  testWidgets('fútbol: usar los pesajes del día, confirmar comparables y guardar', (tester) async {
    final db = openInMemoryDatabase();
    await drive(tester, () async {
      await BodyRepository(db).addWeight(mon, 80.5, moment: WeighMoment.antesFutbol);
      await BodyRepository(db).addWeight(mon, 79.3, moment: WeighMoment.despuesFutbol);
    });
    await mountPushed(tester, base(db), FootballFormScreen(date: mon));
    await tester.tap(find.text('Sí, usarlos'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Minutos'), '60');
    await tester.enterText(find.widgetWithText(TextField, 'Bebido durante (0 si nada)'), '0');
    await settle(tester);
    expect(find.textContaining('Perdiste'), findsNothing, reason: 'sin confirmar comparables no hay cifra');
    expect(find.text('Confirma si son comparables para calcular el sudor.'), findsOneWidget);
    await tester.tap(find.text('Sí, comparables'));
    await settle(tester);
    expect(find.textContaining('Perdiste 1,2 kg'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    final g = (await read(tester, () => db.select(db.footballGames).getSingle()));
    expect((g.weightBeforeKg, g.weightAfterKg, g.fluidMl, g.weightsComparable), (80.5, 79.3, 0, true));
    await drive(tester, db.close);
  });

  testWidgets('fútbol: no son de este partido, faltan datos y "Completar" no guarda; "Guardar así" sí', (tester) async {
    final db = openInMemoryDatabase();
    await drive(tester, () => BodyRepository(db).addWeight(mon, 80.5, moment: WeighMoment.antesFutbol));
    await mountPushed(tester, base(db), FootballFormScreen(date: mon));
    await tester.tap(find.text('No son de este'));
    await settle(tester);
    expect(find.textContaining('¿Son de este partido?'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Minutos'), '45');
    await tester.enterText(find.widgetWithText(TextField, 'Peso antes'), '81');
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect(find.text('Falta para la hidratación'), findsOneWidget);
    await tester.tap(inDialog('Completar'));
    await settle(tester);
    expect(find.text('Falta para la hidratación'), findsNothing);
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    await tester.tap(inDialog('Guardar así'));
    await settle(tester);
    final g = (await read(tester, () => db.select(db.footballGames).getSingle()));
    expect((g.weightBeforeKg, g.weightAfterKg, g.fluidMl, g.weightsComparable), (81.0, null, null, null),
        reason: 'agua desconocida queda null; sin los dos pesajes no hay comparabilidad');
    await drive(tester, db.close);
  });

  testWidgets('fútbol: editar un partido muestra sus valores y no ofrece los del día', (tester) async {
    final db = openInMemoryDatabase();
    final row = await drive(tester, () async {
      await BodyRepository(db).addWeight(mon, 70, moment: WeighMoment.antesFutbol);
      final id = await db.into(db.footballGames).insert(FootballGamesCompanion.insert(
          date: '2030-03-04', minutes: 50, weightBeforeKg: const Value(82), weightsComparable: const Value(false)));
      return (db.select(db.footballGames)..where((t) => t.id.equals(id))).getSingle();
    });
    await mountPushed(tester, base(db), FootballFormScreen(existing: row));
    final texts = tester.widgetList<TextField>(find.byType(TextField)).map((f) => f.controller?.text).toList();
    expect(texts, contains('82'));
    expect(texts, isNot(contains('70')));
    expect(find.textContaining('¿Son de este partido?'), findsNothing);
    await read(tester, () async {});
    await drive(tester, db.close);
  });

  testWidgets('pendiente: Cancelar no toca nada; Desactivar sólo ese', (tester) async {
    final db = openInMemoryDatabase();
    await drive(
        tester,
        () => db.customStatement('insert into custom_reminders (title, interval_days, hour, minute, start_date, enabled) '
            "values ('Uno', 1, 8, 0, '2030-03-01', 1), ('Dos', 1, 8, 0, '2030-03-01', 1)"));
    await mount(tester, base(db), const Scaffold(body: SingleChildScrollView(child: TodayCustomRemindersCard())));
    await tester.tap(find.widgetWithText(TextButton, 'Quitar').first);
    await settle(tester);
    await tester.tap(inDialog('Cancelar'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Quitar').first);
    await settle(tester);
    await tester.tap(inDialog('Desactivar'));
    await settle(tester);
    final rows = await read(tester, () => db.select(db.customReminders).get());
    expect({for (final r in rows) r.title: r.enabled}, {'Uno': false, 'Dos': true});
    await drive(tester, db.close);
  });
}
