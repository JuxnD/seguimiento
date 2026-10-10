import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';

void main() {
  test('desplazamiento cero conserva exactamente geometría histórica en 61 muestras', () {
    final expected = jsonDecode(File('test/fixtures/illustration_legacy_929.json').readAsStringSync()) as Map;
    expect(expected['sourceSha'], '929f2897c73a86760cc73ce228a89f3aaa3789a8');
    final hashes = expected['pointDigests'] as Map;
    final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
    for (final entry in hashes.entries) {
      final fig = catalog.forExercise(entry.key as String)!;
      final samples = [];
      for (var i = 0; i <= 60; i++) {
        final skeleton = fig.skeletonAt(i / 60), body = liftSkeleton(skeleton, fig);
        samples.add({
          'flat': {
            for (final k in (skeleton.joints.keys.toList()..sort())) k: [skeleton.joints[k]!.dx, skeleton.joints[k]!.dy]
          },
          'body': {
            for (final k in (body.p.keys.toList()..sort())) k: [body.p[k]!.x, body.p[k]!.y, body.p[k]!.z]
          }
        });
      }
      expect(sha256.convert(utf8.encode(jsonEncode(samples))).toString(), entry.value,
          reason: '${fig.name}: default0 no altera figura previa');
    }
  });
}
