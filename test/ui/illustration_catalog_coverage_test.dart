import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/catalog_updates.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/mobility.dart';
import 'package:seguimiento/domain/warmup.dart';
import 'package:seguimiento/domain/session_script.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';

void main() {
  test('cada guía, peldaño y ejercicio de movilidad tiene su propia ilustración', () {
    final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
    final expected = <String>{
      ...exerciseGuides.map((e) => e.name),
      ...dragonFlagLadder.steps.map((e) => e.exercise),
      ...vUpLadder.steps.map((e) => e.exercise),
      ...mobilityNight.exercises.map((e) => e.name),
      ...legRecovery.exercises.map((e) => e.name),
      ...warmupMobility.map((e) => e.$1),
      ...warmupForZone.values,
      for (final type in [DayType.circuito, DayType.bloques])
        for (final exercise in ['Dominadas', 'Flexiones', 'Sentadillas'])
          ...buildWarmup(ScriptDay(type: type, exercises: [ScriptExercise(name: exercise)])).map((e) => e.exercise),
    };
    final missing = expected.where((name) => catalog.forExercise(name) == null).toList();
    expect(missing, isEmpty, reason: 'No ocultar un hueco con SizedBox vacío: ${missing.join(', ')}');
    for (final name in expected) {
      final figure = catalog.forExercise(name)!;
      expect(figure.frames.length, greaterThanOrEqualTo(2), reason: name);
      expect(figure.frames.every((frame) => frame.caption.trim().isNotEmpty), isTrue, reason: name);
    }
  });
}
