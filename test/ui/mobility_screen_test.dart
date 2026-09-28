import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
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

/// Rutina corta: un ejercicio por tiempo por lado y uno por repeticiones.
const _routine = MobilityRoutine(
  id: 'prueba',
  name: 'Movilidad de prueba',
  exercises: [
    MobilityExercise(name: 'Flexor de cadera', durationSec: 10, perSide: true, formCues: ['Aprieta el glúteo.']),
    MobilityExercise(name: 'Tobillo a la pared', reps: 10),
  ],
);

void main() {
  test('el guion recorre cada lado y cada serie en orden', () {
    final steps = buildMobilityScript(mobilityNight);
    // 4 ejercicios por lado (8 pasos) + colgado pasivo 2 series.
    expect(steps, hasLength(10));
    expect(steps.first.detail, 'Lado izquierdo');
    expect(steps[1].detail, 'Lado derecho');
    expect(steps.last.detail, 'Serie 2/2');
    expect(steps.last.target, '25 s');
    expect(steps[2].target, '8 reps');
    // Sin contar lo que tarda cambiar de ejercicio, cabe en 5–10 min.
    expect(estimatedMobilitySec(steps), inInclusiveRange(300, 600));
  });

  testWidgets('lo que va por tiempo avanza solo y lo de repeticiones con "Hecho"', (tester) async {
    wakelock.wakelockPlusPlatformInstance = _NoWakelock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    MobilityResult? result;
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
                  context, MaterialPageRoute(builder: (_) => const MobilityScreen(routine: _routine))),
              child: const Text('abrir'),
            ),
          ),
        )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Flexor de cadera'), findsOneWidget);
    expect(find.text('Lado izquierdo'), findsOneWidget);
    expect(find.text('Colócate'), findsOneWidget, reason: 'primero 5 s para colocarse');
    expect(find.text('• Aprieta el glúteo.'), findsOneWidget);

    // 5 s de preparación + 10 s de aguante: pasa solo al otro lado.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Lado derecho'), findsOneWidget);

    await tester.tap(find.text('Saltar'));
    await tester.pump();
    expect(find.text('Tobillo a la pared'), findsOneWidget);
    expect(find.text('10 reps'), findsOneWidget);

    await tester.tap(find.text('Hecho'));
    await tester.pump();
    expect(find.text('Rutina completa'), findsOneWidget);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(result!.complete, isTrue);
    expect(result!.stepsTotal, 3);
    expect(result!.totalSec, greaterThanOrEqualTo(15));
  });
}
