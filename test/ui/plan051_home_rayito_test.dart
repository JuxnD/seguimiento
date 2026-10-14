import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/rayito_widget_bridge.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/mascot.dart';
import 'package:seguimiento/features/home/home_screen.dart';
import 'package:seguimiento/ui/theme.dart';
import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';
import '../support/capture_theme.dart';

class _Day extends TodayNotifier {
  @override
  DateTime build() => DateTime(2030, 3, 4);
}

class _Bridge extends RayitoWidgetBridge {
  _Bridge() : super(android: false);
  final sent = <RayitoWidgetData>[];
  @override
  Future<bool> update(RayitoWidgetData data) async {
    sent.add(data);
    return true;
  }
}

void main() {
  setUpAll(useHostSqlite);
  Future<T> drive<T>(WidgetTester tester, Future<T> Function() fn) async {
    var done = false;
    T? result;
    Object? error;
    unawaited(fn().then((v) {
      result = v;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    }));
    for (var i = 0; i < 200 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    if (!done) fail('SQLite no terminó');
    if (error != null) throw error!;
    return result as T;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
  }

  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets(
        'Hoy real guarda movilidad y Rayito/widget se actualizan, texto x$scale',
        (tester) async {
      await loadTestFonts(tester, realDefaultFont: true);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = openInMemoryDatabase();
      final temp = Directory.systemTemp.createTempSync('myprime051');
      final ex = ExerciseRepository(db);
      final plan = PlanRepository(db, ex);
      final training = TrainingRepository(db, ex);
      final day = DateTime(2030, 3, 4);
      await drive(tester, () async {
        final setup = SetupDraft(startDate: day, stepsTarget: 5000)
          ..clearNutrition();
        if (!await ProfileRepository(db).confirmSetup(setup, now: day)) {
          throw StateError('Alta sintética no confirmada');
        }
        final draft = PlanDraft.empty(day);
        draft.days[0].type = DayType.trenSuperior;
        await plan.saveAsNewVersion(draft);
      });
      final bridge = _Bridge();
      final key = GlobalKey();
      await tester.pumpWidget(ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            localFlagsProvider
                .overrideWithValue(LocalFlags(File('${temp.path}/flags.json'))),
            todayProvider.overrideWith(_Day.new),
            rayitoWidgetBridgeProvider.overrideWithValue(bridge),
            activeSessionProvider.overrideWith((ref) => null),
            updateCheckProvider.overrideWith(
                (ref) => const UpdateCheck(currentVersion: '1.25.0')),
            morningDoneProvider.overrideWith((ref, _) => false),
          ],
          child: MaterialApp(
              theme: captureTheme(buildGymTheme()),
              builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: RepaintBoundary(key: key, child: const HomeScreen()))));
      await settle(tester);
      expect(find.text('Nivel 1 de 8 · Sin racha todavía'), findsOneWidget);
      expect(bridge.sent.last.streak, 0);
      expect(bridge.sent.last.date, day);
      await drive(
          tester,
          () => training.save(SessionDraft(
              date: day,
              type: SessionType.movilidad,
              totalSec: 60,
              incomplete: true)));
      await settle(tester);
      expect(find.text('Nivel 2 de 8 · 1 día de racha'), findsOneWidget);
      expect(bridge.sent.last.mood, MascotMood.contento);
      expect(bridge.sent.last.streak, 1);
      expect(bridge.sent.last.today, 'Tren superior');
      final error = tester.takeException();
      expect(error, isNull);
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      File('build/qa/051/hoy-fonts-v3-x$scale.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await drive(tester, db.close);
      temp.deleteSync(recursive: true);
    });
  }
}
