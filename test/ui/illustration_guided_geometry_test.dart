import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';

void main() {
  final data = jsonDecode(File(Figure3DCatalog.asset).readAsStringSync()) as Map<String, Object?>;
  final catalog = Figure3DCatalog.fromJsonString(jsonEncode(data));
  final figures = <String, Figure3D>{
    for (final raw in (data['figures'] as List).cast<Map<String, Object?>>())
      if ((raw['source'] as String).startsWith('Plan v3.2'))
        raw['name'] as String: catalog.forExercise(raw['name'] as String)!,
    for (final raw in (data['physicalVariants'] as List).cast<Map<String, Object?>>())
      raw['key'] as String: catalog.forExercise(raw['exercise'] as String, physicalVariantKey: raw['key'] as String)!,
  };

  test('guided figures keep bone lengths and finite reachable supports through every stage', () {
    final failures = <String>[];
    for (final entry in figures.entries) {
      final fig = entry.value;
      for (var sample = 0; sample <= fig.motion.length * 20; sample++) {
        final progress = sample / (fig.motion.length * 20);
        try {
          final body = liftSkeleton(fig.skeletonAt(progress), fig);
          for (final side in ['near', 'far']) {
            for (final spec in [
              ('Shoulder', 'Elbow', 10.0),
              ('Elbow', 'Hand', 9.0),
              ('Hip', 'Knee', 14.0),
              ('Knee', 'Ankle', 14.0)
            ]) {
              final length = (body.p['$side${spec.$1}']! - body.p['$side${spec.$2}']!).length;
              if (!length.isFinite || (length - spec.$3).abs() > .4) {
                if (failures.length < 80) failures.add('${entry.key}/$sample/$side${spec.$2}: $length');
              }
            }
          }
        } on FormatException catch (e) {
          if (failures.length < 80) failures.add('${entry.key}/$sample: $e');
        }
      }
    }
    for (final failure in failures) {
      printOnFailure(failure);
    }
    expect(failures, isEmpty);
  });

  test('guided independent world anchors stay fixed during demonstrated support phases', () {
    const anchors = {
      'Gato-camello': ['nearHand', 'farHand', 'nearKnee', 'farKnee'],
      'Respiración 90/90': ['hip', 'nearKnee', 'farKnee', 'nearAnkle', 'farAnkle'],
      'Muñecas a cuatro patas': ['nearHand', 'farHand', 'nearKnee', 'farKnee'],
      'Pike sentado': ['hip', 'nearAnkle', 'farAnkle'],
      'Pancake': ['hip', 'nearAnkle', 'farAnkle'],
      'Sóleo en la pared': ['nearHand', 'farHand', 'nearAnkle', 'farAnkle'],
      'Rodilla a la pared': ['nearAnkle'],
      'Scap pull-up': ['nearHand', 'farHand'],
      'Tibial en la pared': ['nearAnkle', 'farAnkle'],
      'Sentadilla isométrica en la pared': ['nearAnkle', 'farAnkle'],
      'Nórdico inverso': ['nearKnee', 'farKnee'],
      'Bajada lateral del escalón': ['nearAnkle'],
      'Mesa invertida': ['nearHand', 'farHand', 'nearAnkle', 'farAnkle'],
    };
    final failures = <String>[];
    for (final entry in anchors.entries) {
      final fig = catalog.forExercise(entry.key)!;
      final first = liftSkeleton(fig.skeletonAt(0), fig);
      for (var i = 1; i <= 60; i++) {
        final body = liftSkeleton(fig.skeletonAt(i / 60), fig);
        for (final key in entry.value) {
          final drift = (body.p[key]! - first.p[key]!).length;
          if (drift > .08 && failures.length < 50) failures.add('${entry.key}/$i/$key: $drift');
        }
      }
    }
    expect(failures, isEmpty);
  });

  testWidgets('cat cow breathing and short foot change the rendered anatomy not only captions', (tester) async {
    final unchanged = <String>[];
    for (final name in ['Gato-camello', 'Respiración 90/90', 'Pie corto']) {
      // Remove head-only motion: the torso/foot itself must visibly change.
      final fixture = jsonDecode(jsonEncode(data)) as Map<String, Object?>;
      final raw = (fixture['figures'] as List).cast<Map<String, Object?>>().firstWhere((f) => f['name'] == name);
      for (final frame in (raw['frames'] as List).cast<Map<String, Object?>>()) {
        frame['gaze'] = 0;
      }
      final fig = Figure3DCatalog.fromJsonString(jsonEncode(fixture)).forExercise(name)!;
      final images = <List<int>>[];
      await tester.runAsync(() async {
        for (final progress in [0.0, 1.0 / fig.motion.length]) {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          paintFigure3D(canvas, const ui.Size(420, 360), fig, progress, yaw: fig.initialYaw, pitch: fig.initialPitch);
          final picture = recorder.endRecording();
          final image = await picture.toImage(420, 360);
          images.add((await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
        }
      });
      var changed = 0;
      for (var i = 0; i < images[0].length; i++) {
        if (images[0][i] != images[1][i]) changed++;
      }
      if (changed < 100) unchanged.add('$name: $changed changed channels');
    }
    expect(unchanged, isEmpty);
  });

  test('local spine and bare foot anatomy preserve support and remain readable at phone size', () {
    final cat = catalog.forExercise('Gato-camello')!;
    final rounded = cat.skeletonAt(1 / cat.motion.length), extended = cat.skeletonAt(3 / cat.motion.length);
    final rb = liftSkeleton(rounded, cat), eb = liftSkeleton(extended, cat);
    final neutral = (rb.p['hip']! + rb.p['neck']!) * .5;
    expect((spineCenterline(rb, cat.dims, rounded.spineBend, .5) - neutral).dot(rb.front), lessThan(-.5));
    expect((spineCenterline(eb, cat.dims, extended.spineBend, .5) - neutral).dot(eb.front), greaterThan(.5));
    expect((rb.p['hip']! - eb.p['hip']!).length, lessThan(.001));
    expect((rb.p['neck']! - eb.p['neck']!).length, lessThan(.001));
    final foot = catalog.forExercise('Pie corto')!;
    final start = foot.skeletonAt(0), active = foot.skeletonAt(1 / foot.motion.length);
    final sb = liftSkeleton(start, foot), ab = liftSkeleton(active, foot);
    final a = shortFootLandmarks(sb, start.footArch), b = shortFootLandmarks(ab, active.footArch);
    for (final anchor in ['heel', 'metatarsal', 'toe']) {
      expect((a[anchor]! - b[anchor]!).length, lessThan(.001));
    }
    expect(b['arch']!.y, lessThan(a['arch']!.y - .4));
    expect((b['toe']! - b['metatarsal']!).length, closeTo(1.8, .001));
    final cam = cameraFor(foot, const ui.Size(320, 285), yaw: foot.initialYaw, pitch: foot.initialPitch);
    expect((cam.project(b['toe']!).offset - cam.project(b['heel']!).offset).distance, greaterThan(70));
    expect((cam.project(b['arch']!).offset - cam.project(a['arch']!).offset).distance, greaterThan(5));
  });

  test('physical variants retain their required world support and equipment contacts', () {
    final failures = <String>[];
    void check(String label, double error, [double tolerance = .08]) {
      if (error > tolerance && failures.length < 100) failures.add('$label: $error');
    }

    for (final key in ['copenhagen_short', 'copenhagen_long']) {
      final fig = catalog.forExercise('Copenhague', physicalVariantKey: key)!;
      final support = key.endsWith('long') ? 'nearAnkle' : 'nearKnee';
      final first = liftSkeleton(fig.skeletonAt(0), fig);
      for (var i = 0; i <= 100; i++) {
        final body = liftSkeleton(fig.skeletonAt(i / 100), fig);
        check('$key/elbow/$i', (body.p['farElbow']! - first.p['farElbow']!).length);
        check('$key/support/$i', (body.p[support]! - first.p[support]!).length);
        check('$key/floor/$i', (body.p['farElbow']!.y + 1.2).abs());
        check('$key/bed/$i', (body.p[support]!.y + 19).abs());
      }
      expect((liftSkeleton(fig.skeletonAt(.4), fig).p['hip']! - first.p['hip']!).length, greaterThan(1));
      final seat = (fig.props.first['center'] as List).cast<num>();
      final size = (fig.props.first['size'] as List).cast<num>();
      final surface = seat[1] - size[1] / 2;
      expect(surface, closeTo(key.endsWith('long') ? -18 : -17.4, .001));
    }
    for (final key in ['support_parallels', 'support_rings']) {
      final fig = catalog.forExercise('Support hold en paralelas', physicalVariantKey: key)!;
      final first = liftSkeleton(fig.skeletonAt(0), fig);
      for (var i = 0; i <= 60; i++) {
        final body = liftSkeleton(fig.skeletonAt(i / 60), fig);
        for (final side in ['near', 'far']) {
          check('$key/hand/$side/$i', (body.p['${side}Hand']! - first.p['${side}Hand']!).length);
          check('$key/barHeight/$side/$i', (body.p['${side}Hand']!.y + 29).abs());
          if (body.p['${side}Toe']!.y >= -.9) failures.add('$key free feet/$side/$i');
        }
      }
      final tubes = fig.props.where((p) => p['type'] == 'tube').toList();
      expect(tubes.length, key == 'support_rings' ? 50 : 6);
    }
    for (final key in ['band_rotation_side', 'band_rotation_90_90']) {
      final fig = catalog.forExercise('Rotación externa con banda', physicalVariantKey: key)!;
      final first = liftSkeleton(fig.skeletonAt(0), fig);
      for (var i = 0; i <= 100; i++) {
        final body = liftSkeleton(fig.skeletonAt(i / 100), fig);
        for (final side in ['near', 'far']) {
          check('$key/elbow/$side/$i', (body.p['${side}Elbow']! - first.p['${side}Elbow']!).length);
        }
      }
    }
    for (final key in ['seated_soleus_bilateral', 'seated_soleus_unilateral']) {
      final fig = catalog.forExercise('Sóleo sentado con mochila', physicalVariantKey: key)!;
      final first = liftSkeleton(fig.skeletonAt(0), fig);
      for (var i = 0; i <= 100; i++) {
        final body = liftSkeleton(fig.skeletonAt(i / 100), fig);
        for (final side in ['near', 'far']) {
          check('$key/toe/$side/$i', (body.p['${side}Toe']! - first.p['${side}Toe']!).length);
        }
        if (key.endsWith('unilateral')) check('$key/inactive/$i', (body.p['farAnkle']! - first.p['farAnkle']!).length);
      }
      final peak = fig.motion.indexWhere((stage) => stage.kind == 'hold') / fig.motion.length;
      expect(liftSkeleton(fig.skeletonAt(peak), fig).p['nearAnkle']!.y, lessThan(-2));
    }
    for (final key in ['landing_bilateral', 'landing_unilateral', 'landing_lateral']) {
      final fig = catalog.forExercise('Aterrizaje clavado', physicalVariantKey: key)!;
      final flight = liftSkeleton(fig.skeletonAt(1 / fig.motion.length), fig);
      final landed = liftSkeleton(fig.skeletonAt(2 / fig.motion.length), fig);
      expect(flight.p['nearToe']!.y, lessThan(-5));
      expect(flight.p['farToe']!.y, lessThan(-5));
      expect(landed.p['nearAnkle']!.y, closeTo(-1, .05));
      if (key != 'landing_bilateral') expect(landed.p['farToe']!.y, lessThan(-2));
      for (var i = 0; i <= 20; i++) {
        final held = liftSkeleton(fig.skeletonAt((2 + i / 20) / fig.motion.length), fig);
        check('$key/landed/$i', (held.p['nearAnkle']! - landed.p['nearAnkle']!).length);
      }
    }
    for (final failure in failures) {
      printOnFailure(failure);
    }
    expect(failures, isEmpty);
  });

  test('guided plantar supports never point toes through the ground', () {
    final failures = <String>[];
    for (final name in [
      'Bajada lateral del escalón',
      'Mesa invertida',
      'Rodilla a la pared',
      'Sentadilla isométrica en la pared',
      'Sóleo en la pared',
      'Tibial en la pared',
      'Zancada del mundo'
    ]) {
      final fig = catalog.forExercise(name)!;
      for (var i = 0; i <= 60; i++) {
        final body = liftSkeleton(fig.skeletonAt(i / 60), fig);
        for (final side in ['near', 'far']) {
          final toe = body.p['${side}Toe']!;
          if (toe.y > .1 && failures.length < 40) failures.add('$name/$i/$side toe=$toe');
        }
      }
    }
    expect(failures, isEmpty);
  });

  test('seated soleus keeps knees forward above ankles and raised plank straight', () {
    final failures = <String>[];
    for (final key in ['seated_soleus_bilateral', 'seated_soleus_unilateral']) {
      final fig = catalog.forExercise('Sóleo sentado con mochila', physicalVariantKey: key)!;
      for (var i = 0; i <= 60; i++) {
        final body = liftSkeleton(fig.skeletonAt(i / 60), fig);
        for (final side in ['near', 'far']) {
          final hip = body.p['${side}Hip']!, knee = body.p['${side}Knee']!, ankle = body.p['${side}Ankle']!;
          if (knee.x - hip.x < 12 || (knee.y - hip.y).abs() > 5 || ankle.y - knee.y < 10) {
            failures.add('$key/$i/$side hip=$hip knee=$knee ankle=$ankle');
          }
        }
      }
    }
    final plank = catalog.forExercise('Plancha inversa con pies elevados')!;
    final held = liftSkeleton(plank.skeletonAt(1 / plank.motion.length), plank);
    for (final side in ['near', 'far']) {
      final hip = held.p['${side}Hip']!, knee = held.p['${side}Knee']!, ankle = held.p['${side}Ankle']!;
      if ((knee - hip).unit.dot((ankle - knee).unit) < .999) failures.add('elevated plank $side knee bent');
    }
    expect(failures.take(20), isEmpty);
  });

  test('guided floor hands and bed elbows respect their support surfaces', () {
    final failures = <String>[];
    for (final name in ['Abducción de cadera de lado', 'Zancada del mundo']) {
      final fig = catalog.forExercise(name)!;
      for (var i = 0; i <= 60; i++) {
        final body = liftSkeleton(fig.skeletonAt(i / 60), fig);
        for (final side in ['near', 'far']) {
          if (body.p['${side}Hand']!.y > .1) failures.add('$name/$i/$side hand below floor');
        }
      }
    }
    final dorsal = catalog.forExercise('Dorsal en la cama')!;
    final first = liftSkeleton(dorsal.skeletonAt(0), dorsal);
    for (var i = 0; i <= 60; i++) {
      final body = liftSkeleton(dorsal.skeletonAt(i / 60), dorsal);
      for (final side in ['near', 'far']) {
        final drift = (body.p['${side}Elbow']! - first.p['${side}Elbow']!).length;
        if (drift > .08) failures.add('Dorsal/$i/$side elbow drifts $drift');
      }
    }
    expect(failures.take(30), isEmpty);
  });

  testWidgets('short foot detail leaves breathing room above the ankle instead of cropped shins', (tester) async {
    final fig = catalog.forExercise('Pie corto')!;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      paintFigure3D(ui.Canvas(recorder), const ui.Size(360, 315), fig, 0, yaw: fig.initialYaw, pitch: fig.initialPitch);
      final picture = recorder.endRecording();
      final image = await picture.toImage(360, 315);
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      var filled = 0;
      for (var y = 0; y < 24; y++) {
        for (var x = 0; x < 360; x++) {
          if (rgba[(y * 360 + x) * 4 + 3] > 0) filled++;
        }
      }
      image.dispose();
      picture.dispose();
      expect(filled, 0,
          reason: 'The foot detail must show its whole short ankle, without a shin cropped by the top edge.');
    });
  });

  testWidgets('external rotation band remains visibly connected between the opened hands', (tester) async {
    final fig = catalog.forExercise('Rotación externa con banda')!;
    final progress = 8 / fig.motion.length;
    final body = liftSkeleton(fig.skeletonAt(progress), fig);
    final camera = cameraFor(fig, const ui.Size(360, 315), yaw: fig.initialYaw, pitch: fig.initialPitch);
    final projected = (camera.project(body.p['nearHand']!).offset - camera.project(body.p['farHand']!).offset).distance;
    expect(projected, greaterThan(25), reason: 'The default view must separate the two hands.');
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      paintFigure3D(ui.Canvas(recorder), const ui.Size(360, 315), fig, progress,
          yaw: fig.initialYaw, pitch: fig.initialPitch);
      final picture = recorder.endRecording();
      final image = await picture.toImage(360, 315);
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      var visible = 0;
      for (var i = 0; i < rgba.length; i += 4) {
        if (rgba[i] < 100 && rgba[i + 1] > 170 && rgba[i + 2] > 150 && rgba[i + 3] > 200) visible++;
      }
      image.dispose();
      picture.dispose();
      expect(visible, greaterThan(projected),
          reason: 'A 3px band spanning the hands must remain mostly visible, not just an endpoint dot.');
    });
  });

  test('accessory physical levels preserve straight tibial knees bed support and support hands', () {
    for (final key in ['tibialis_wall_close', 'tibialis_wall_far', 'tibialis_wall_loaded']) {
      final fig = catalog.forExercise('Tibial en la pared', physicalVariantKey: key)!;
      final start = liftSkeleton(fig.skeletonAt(0), fig);
      for (var i = 0; i <= 40; i++) {
        final body = liftSkeleton(fig.skeletonAt(i / 40), fig);
        for (final side in ['near', 'far']) {
          final hip = body.p['${side}Hip']!, knee = body.p['${side}Knee']!, ankle = body.p['${side}Ankle']!;
          expect((knee - hip).unit.dot((ankle - knee).unit), greaterThan(.9999), reason: key);
          expect((ankle - start.p['${side}Ankle']!).length, lessThan(.001), reason: key);
        }
      }
    }
    for (final key in ['prone_y_t_bed_edge', 'prone_y_t_loaded']) {
      final fig = catalog.forExercise('Y-T prono', physicalVariantKey: key)!;
      final rest = liftSkeleton(fig.skeletonAt(0), fig);
      final raised = liftSkeleton(fig.skeletonAt(1 / fig.motion.length), fig);
      expect(rest.p['hip']!.y, closeTo(-19.5, .01));
      expect(rest.p['nearHand']!.y - rest.p['nearShoulder']!.y, greaterThan(15));
      expect(raised.p['nearHand']!.y, lessThan(raised.p['nearShoulder']!.y - 1));
      expect((raised.p['hip']! - rest.p['hip']!).length, lessThan(.001));
    }
    final support = catalog.forExercise('Support hold en paralelas', physicalVariantKey: 'support_protraction')!;
    final start = liftSkeleton(support.skeletonAt(0), support);
    final end = liftSkeleton(support.skeletonAt(1 / support.motion.length), support);
    expect((end.p['hip']! - start.p['hip']!).length, greaterThan(.8));
    for (final side in ['near', 'far']) {
      expect((end.p['${side}Hand']! - start.p['${side}Hand']!).length, lessThan(.001));
      expect((end.p['${side}Hand']! - end.p['${side}Shoulder']!).length, closeTo(19, .03));
    }
  });

  testWidgets('accessory loads are really painted at the selected limb rather than metadata only', (tester) async {
    for (final spec in [('Tibial en la pared', 'tibialis_wall_loaded'), ('Y-T prono', 'prone_y_t_loaded')]) {
      final original = catalog.forExercise(spec.$1, physicalVariantKey: spec.$2)!;
      final stripped = jsonDecode(jsonEncode(data)) as Map<String, Object?>;
      final variant =
          (stripped['physicalVariants'] as List).cast<Map<String, Object?>>().firstWhere((v) => v['key'] == spec.$2);
      final raw = variant['figure'] as Map<String, Object?>;
      (raw['props'] as List).removeWhere((p) => ((p as Map<String, Object?>)['type'] as String).startsWith('guided'));
      final bare =
          Figure3DCatalog.fromJsonString(jsonEncode(stripped)).forExercise(spec.$1, physicalVariantKey: spec.$2)!;
      await tester.runAsync(() async {
        final images = <List<int>>[];
        for (final fig in [original, bare]) {
          final recorder = ui.PictureRecorder();
          paintFigure3D(ui.Canvas(recorder), const ui.Size(420, 360), fig, 1 / fig.motion.length,
              yaw: original.initialYaw, pitch: original.initialPitch);
          final picture = recorder.endRecording();
          final image = await picture.toImage(420, 360);
          images.add((await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
        }
        var changed = 0;
        for (var i = 0; i < images[0].length; i += 4) {
          if (images[0][i] != images[1][i] ||
              images[0][i + 1] != images[1][i + 1] ||
              images[0][i + 2] != images[1][i + 2]) changed++;
        }
        expect(changed, greaterThan(100), reason: '${spec.$2}: actual load must be visible in the production painter.');
      });
    }
  });

  test('deep squat hold goes below the knees with elbows between them and heels planted', () {
    final fig=catalog.forExercise('Sentadilla profunda')!;
    final start=liftSkeleton(fig.skeletonAt(0),fig);
    final held=liftSkeleton(fig.skeletonAt(1/fig.motion.length),fig);
    for(final side in ['near','far']) {
      final hip=held.p['${side}Hip']!, knee=held.p['${side}Knee']!, elbow=held.p['${side}Elbow']!;
      expect(hip.y-knee.y,greaterThan(1),reason:'Deep squat requires hips below the knees.');
      expect((elbow.y-knee.y).abs(),lessThan(5),reason:'Elbows shown between the knees must be close to knee height.');
      expect(elbow.z.abs(),lessThan(knee.z.abs()));
      expect((held.p['${side}Ankle']!-start.p['${side}Ankle']!).length,lessThan(.001));
    }
  });

}
