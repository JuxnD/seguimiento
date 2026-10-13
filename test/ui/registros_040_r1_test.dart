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
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/recovery.dart' show WeighMoment;
import 'package:seguimiento/features/home/home_screen.dart';
import 'package:seguimiento/features/training/football_form_screen.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/sqlite_host.dart';

/// Observaciones previas a R1 de 040, en pantalla. Fechas ficticias.
class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2030, 3, 4);
}

/// Pesajes que sólo responden cuando la prueba abre la compuerta de ese día:
/// así se ordenan las respuestas sin esperas ni tiempos.
class _GatedBody extends BodyRepository {
  _GatedBody(super.db);

  final gates = <String, Completer<void>>{};

  @override
  Future<List<BodyWeightRow>> weightsOn(DateTime date) async {
    await (gates[dayKey(date)] ??= Completer<void>()).future;
    return super.weightsOn(date);
  }
}

void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2030, 3, 4);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('seguimiento_040_r1'));

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

  Future<T> read<T>(WidgetTester tester, Future<T> Function() op) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    return drive(tester, op);
  }

  Finder inDialog(String text) => find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  testWidgets('cambiar la fecha rápido: la respuesta vieja no se ofrece como del día nuevo', (tester) async {
    final db = openInMemoryDatabase();
    final body = _GatedBody(db);
    await drive(tester, () async {
      await BodyRepository(db).addWeight(mon, 80.5, moment: WeighMoment.antesFutbol); // lunes
      await BodyRepository(db).addWeight(DateTime(2030, 3, 5), 77.7, moment: WeighMoment.antesFutbol); // martes
    });
    await mountPushed(tester, [...base(db), bodyRepositoryProvider.overrideWithValue(body)], FootballFormScreen(date: mon));
    // Mientras el lunes sigue consultando, se elige el martes.
    await tester.tap(find.textContaining('4 mar'));
    await settle(tester);
    final picker = find.byType(DatePickerDialog);
    await tester.tap(find.descendant(of: picker, matching: find.text('5')).first);
    await tester.tap(find.descendant(of: picker, matching: find.text('OK')));
    await settle(tester);
    // Responde primero el martes y después el lunes (orden inverso).
    body.gates['2030-03-05']!.complete();
    await settle(tester);
    body.gates['2030-03-04']!.complete();
    await settle(tester);
    expect(find.textContaining('antes 77,7 kg'), findsOneWidget);
    expect(find.textContaining('80,5'), findsNothing, reason: 'el pesaje del lunes no se ofrece para el martes');
    await read(tester, () async {});
    await drive(tester, db.close);
  });

  testWidgets('confirmar comparables y luego cambiar un peso: la cifra se va hasta confirmar otra vez', (tester) async {
    final db = openInMemoryDatabase();
    await mountPushed(tester, base(db), FootballFormScreen(date: mon));
    await tester.enterText(find.widgetWithText(TextField, 'Minutos'), '60');
    await tester.enterText(find.widgetWithText(TextField, 'Peso antes'), '80');
    await tester.enterText(find.widgetWithText(TextField, 'Peso después'), '79');
    await tester.enterText(find.widgetWithText(TextField, 'Bebido durante (0 si nada)'), '500');
    await settle(tester);
    await tester.tap(find.text('Sí, comparables'));
    await settle(tester);
    expect(find.textContaining('Perdiste 1 kg'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Peso después'), '78,8');
    await settle(tester);
    expect(find.textContaining('Perdiste'), findsNothing, reason: 'otro peso: lo confirmado ya no vale');
    expect(find.text('Confirma si son comparables para calcular el sudor.'), findsOneWidget);
    await tester.tap(find.text('Sí, comparables'));
    await settle(tester);
    expect(find.textContaining('Perdiste 1,2 kg'), findsOneWidget);
    await read(tester, () async {});
    await drive(tester, db.close);
  });

  testWidgets('editar un partido confirmado conserva su confirmación mientras no cambien los pesajes', (tester) async {
    final db = openInMemoryDatabase();
    final row = await drive(tester, () async {
      final id = await db.into(db.footballGames).insert(FootballGamesCompanion.insert(
          date: '2030-03-04',
          minutes: 60,
          weightBeforeKg: const Value(80),
          weightAfterKg: const Value(79),
          fluidMl: const Value(0),
          weightsComparable: const Value(true)));
      return (db.select(db.footballGames)..where((t) => t.id.equals(id))).getSingle();
    });
    await mountPushed(tester, base(db), FootballFormScreen(existing: row));
    expect(find.textContaining('Perdiste 1 kg'), findsOneWidget);
    await read(tester, () async {});
    await drive(tester, db.close);
  });

  testWidgets('el texto de comparables no prohíbe el agua que la fórmula descuenta', (tester) async {
    final db = openInMemoryDatabase();
    await mountPushed(tester, base(db), FootballFormScreen(date: mon));
    await tester.enterText(find.widgetWithText(TextField, 'Peso antes'), '80');
    await tester.enterText(find.widgetWithText(TextField, 'Peso después'), '79');
    await settle(tester);
    expect(find.textContaining('sin comer ni beber'), findsNothing);
    expect(find.textContaining('Lo bebido durante se descuenta aparte'), findsOneWidget);
    await read(tester, () async {});
    await drive(tester, db.close);
  });

  testWidgets('noche de 0 h de antes: editar sólo la nota la conserva', (tester) async {
    final db = openInMemoryDatabase();
    await drive(tester, () => db.customStatement("insert into sleep_logs (date, hours) values ('2030-03-04', 0)"));
    await mount(
        tester,
        [
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
        ],
        const HomeScreen());
    final line = find.textContaining('Anoche:');
    await tester.scrollUntilVisible(line, 120, scrollable: find.byType(Scrollable).first);
    await tester.tap(line);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nota (opcional)'), 'no dormí');
    await tester.tap(inDialog('Guardar'));
    await settle(tester);
    expect(find.textContaining('Escribe horas'), findsNothing, reason: 'no obliga a reescribir el 0');
    final d = (await read(tester, () => SleepRepository(db).detail(mon)))!;
    expect((d.hours, d.note), (0.0, 'no dormí'));
    await drive(tester, db.close);
  });
}
