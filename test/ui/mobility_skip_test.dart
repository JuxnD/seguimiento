import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/domain/daily_routines.dart';
import 'package:seguimiento/domain/mobility.dart';
import 'package:seguimiento/features/training/mobility_screen.dart';
import 'package:seguimiento/features/training/technique_sheet.dart';
import 'package:seguimiento/ui/exercise_art.dart';
import 'package:seguimiento/ui/exercise_figure.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

/// R2 de 032: "Saltar" avanza pero no cuenta como hecho. Una rutina con algo
/// omitido queda a medias (sin ✓ ni racha); hecha paso a paso, completa.
const _exercises = [
  MobilityExercise(name: 'Flexor de cadera', durationSec: 10, perSide: true, formCues: ['Aprieta el glúteo.']),
  MobilityExercise(name: 'Tobillo a la pared', reps: 10),
];

void main() {
  MobilityResult? result;

  Future<void> open(WidgetTester tester, MobilityRoutine routine) async {
    result = null;
    wakelock.wakelockPlusPlatformInstance = _NoWakelock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final art = ExerciseArtCatalog.fromJsonString(File(ExerciseArtCatalog.asset).readAsStringSync());
    await tester.pumpWidget(ProviderScope(
        overrides: [
          exerciseArtProvider.overrideWith((ref) => art),
          exercisePhotoProvider.overrideWith((ref, _) => Stream.value(null)),
          documentsDirProvider.overrideWith((ref) => Directory.systemTemp),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.push<MobilityResult>(
                  context, MaterialPageRoute(builder: (_) => MobilityScreen(routine: routine))),
              child: const Text('abrir'),
            ),
          ),
        )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<MobilityResult> save(WidgetTester tester) async {
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    return result!;
  }

  testWidgets('saltar todo lo que se puede y terminar: a medias, 0 hechos', (tester) async {
    await open(tester, const MobilityRoutine(id: 'prueba', name: 'Prueba', exercises: _exercises));
    await tester.tap(find.text('Saltar')); // lado izquierdo
    await tester.pump();
    await tester.tap(find.text('Saltar')); // lado derecho
    await tester.pump();
    expect(find.text('Tobillo a la pared'), findsOneWidget);
    await tester.tap(find.text('Terminar'));
    await tester.pump();
    expect(find.text('Rutina a medias'), findsOneWidget);
    expect(find.text('2 pasos saltados'), findsOneWidget);
    final r = await save(tester);
    expect((r.complete, r.stepsDone, r.stepsTotal), (false, 0, 3));
  });

  testWidgets('hecha paso a paso (tiempo que se agota y "Hecho"): completa', (tester) async {
    await open(tester, const MobilityRoutine(id: 'prueba', name: 'Prueba', exercises: _exercises));
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Tobillo a la pared'), findsOneWidget);
    await tester.tap(find.text('Hecho'));
    await tester.pump();
    expect(find.text('Rutina completa'), findsOneWidget);
    expect(find.textContaining('saltad'), findsNothing);
    final r = await save(tester);
    expect((r.complete, r.stepsDone, r.stepsTotal), (true, 3, 3));
  });

  testWidgets('recuperación a medias: constancia sólo al guardar, recuperación hecha no', (tester) async {
    await open(tester, const MobilityRoutine(id: recoveryActiveId, name: 'Recuperación activa', exercises: _exercises));
    await tester.tap(find.text('Saltar'));
    await tester.pump();
    await tester.tap(find.text('Terminar'));
    await tester.pump();
    expect(find.text('Rutina a medias'), findsOneWidget);
    expect(find.textContaining('mantiene la racha y no suma carga'), findsNothing);
    expect(find.text('Al guardar, mantiene la racha de actividad; no suma carga ni cuenta como recuperación hecha.'),
        findsOneWidget);
  });
}
