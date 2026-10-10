import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import '../fixtures/illustration_legacy_929/exercise_figure_3d_reference.dart' as legacy;

void main() {
  test('desplazamiento cero conserva exactamente geometría histórica en 61 muestras', () {
    final expected = jsonDecode(File('test/fixtures/illustration_legacy_929.json').readAsStringSync()) as Map;
    expect(expected['sourceSha'], '929f2897c73a86760cc73ce228a89f3aaa3789a8');
    const reference = 'test/fixtures/illustration_legacy_929';
    final manifest = jsonDecode(File('$reference/manifest.json').readAsStringSync()) as Map;
    expect(manifest['sourceSha'], expected['sourceSha']);
    expect(manifest['samplesPerFigure'], 61);
    final assetBytes = File('$reference/figuras3d.json').readAsBytesSync();
    expect(sha256.convert(assetBytes).toString(), expected['sourceAssetSha256']);
    expect(manifest['sourceAssetSha256'], expected['sourceAssetSha256']);
    final sourceBytes = File('$reference/exercise_figure_3d_reference.dart').readAsBytesSync();
    expect(sha256.convert(sourceBytes).toString(), manifest['referenceSourceSha256']);
    final transform = manifest['transformation'] as Map;
    final source = utf8.decode(sourceBytes);
    final adaptedImport = transform['to'] as String;
    expect(adaptedImport.allMatches(source).length, 1);
    expect(sha256.convert(utf8.encode(source.replaceFirst(adaptedImport, transform['from'] as String))).toString(),
        '0fd1b6b9dcd4d284f8d7c36ddeef4a3a08a527a5e0b92c54425289f6e56bd7fd');
    final hashes = expected['pointDigests'] as Map;
    final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
    final referenceCatalog = legacy.Figure3DCatalog.fromJsonString(utf8.decode(assetBytes));
    expect(referenceCatalog.all.map((f) => f.name).toSet(), hashes.keys.toSet());
    for (final entry in hashes.entries) {
      final fig = catalog.forExercise(entry.key as String)!;
      final previous = referenceCatalog.forExercise(entry.key as String)!;
      for (var i = 0; i <= 60; i++) {
        final oldSkeleton = previous.skeletonAt(i / 60), oldBody = legacy.liftSkeleton(oldSkeleton, previous);
        final skeleton = fig.skeletonAt(i / 60), body = liftSkeleton(skeleton, fig);
        expect(skeleton.joints, oldSkeleton.joints, reason: '${fig.name}: muestra $i/60, coordenadas 2D exactas');
        expect({for (final e in body.p.entries) e.key: [e.value.x, e.value.y, e.value.z]},
            {for (final e in oldBody.p.entries) e.key: [e.value.x, e.value.y, e.value.z]},
            reason: '${fig.name}: muestra $i/60, coordenadas 3D exactas');
      }
    }
  });
}
