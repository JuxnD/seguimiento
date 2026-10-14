import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import '../fixtures/illustration_legacy_929/exercise_figure_3d_reference.dart' as legacy;

void main() {
  test('rig conserva73 figuras históricas y catálogo no seleccionado035 en61 muestras', () {
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
    // Run every historical pose through the current rig, without replacing
    // its frozen input with newly authored poses. Selected035 figures have
    // their own geometric/contact oracles; all other current figures must
    // also remain bit-for-bit equal to the independent historical rig.
    final catalog = Figure3DCatalog.fromJsonString(utf8.decode(assetBytes));
    final current = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
    const selected035 = {
      '90/90 de cadera',
      'Aceleración 10–20 m',
      'Barca / V-sit',
      'Burpees',
      'Calentamiento tipo FIFA 11+',
      'Carga abrazada al pecho',
      'Carga de maleta con mochila',
      'Colgarse de la barra',
      'Colgado pasivo',
      'Curl con banda',
      'Dragon flag',
      'Dominadas',
      'Elevaciones en straddle',
      'Negativo de dragon flag',
      'Negativo de dragon flag a una pierna',
      'Negativo de dragon flag recogido',
      'Vela',
    };
    final referenceCatalog = legacy.Figure3DCatalog.fromJsonString(utf8.decode(assetBytes));
    expect(referenceCatalog.all.map((f) => f.name).toSet(), hashes.keys.toSet());
    for (final entry in hashes.entries) {
      final previous = referenceCatalog.forExercise(entry.key as String)!;
      final candidates = [
        catalog.forExercise(entry.key as String)!,
        if (!selected035.contains(entry.key)) current.forExercise(entry.key as String)!,
      ];
      for (final fig in candidates) {
        for (var i = 0; i <= 60; i++) {
          final oldSkeleton = previous.skeletonAt(i / 60), oldBody = legacy.liftSkeleton(oldSkeleton, previous);
          final skeleton = fig.skeletonAt(i / 60), body = liftSkeleton(skeleton, fig);
          expect(skeleton.joints, oldSkeleton.joints, reason: '${fig.name}: muestra $i/60, coordenadas 2D exactas');
          expect({
            for (final e in body.p.entries) e.key: [e.value.x, e.value.y, e.value.z]
          }, {
            for (final e in oldBody.p.entries) e.key: [e.value.x, e.value.y, e.value.z]
          }, reason: '${fig.name}: muestra $i/60, coordenadas 3D exactas');
        }
      }
    }
  });
}
