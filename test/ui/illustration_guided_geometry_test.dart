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
            for (final spec in [('Shoulder','Elbow',10.0),('Elbow','Hand',9.0),('Hip','Knee',14.0),('Knee','Ankle',14.0)]) {
              final length = (body.p['$side${spec.$1}']! - body.p['$side${spec.$2}']!).length;
              if (!length.isFinite || (length-spec.$3).abs()>.4) {
                if (failures.length<80) failures.add('${entry.key}/$sample/$side${spec.$2}: $length');
              }
            }
          }
        } on FormatException catch (e) {
          if (failures.length<80) failures.add('${entry.key}/$sample: $e');
        }
      }
    }
    expect(failures,isEmpty);
  });

  test('guided independent world anchors stay fixed during demonstrated support phases', () {
    const anchors = {
      'Gato-camello': ['nearHand','farHand','nearKnee','farKnee'],
      'Respiración 90/90': ['hip','nearKnee','farKnee','nearAnkle','farAnkle'],
      'Muñecas a cuatro patas': ['nearHand','farHand','nearKnee','farKnee'],
      'Pike sentado': ['hip','nearAnkle','farAnkle'],
      'Pancake': ['hip','nearAnkle','farAnkle'],
      'Sóleo en la pared': ['nearHand','farHand','nearAnkle','farAnkle'],
      'Rodilla a la pared': ['nearAnkle'],
      'Scap pull-up': ['nearHand','farHand'],
      'Tibial en la pared': ['nearAnkle','farAnkle'],
      'Sentadilla isométrica en la pared': ['nearAnkle','farAnkle'],
      'Nórdico inverso': ['nearKnee','farKnee'],
      'Bajada lateral del escalón': ['nearAnkle'],
      'Mesa invertida': ['nearHand','farHand','nearAnkle','farAnkle'],
    };
    final failures=<String>[];
    for (final entry in anchors.entries) {
      final fig=catalog.forExercise(entry.key)!;
      final first=liftSkeleton(fig.skeletonAt(0),fig);
      for(var i=1;i<=60;i++) {
        final body=liftSkeleton(fig.skeletonAt(i/60),fig);
        for(final key in entry.value) {
          final drift=(body.p[key]!-first.p[key]!).length;
          if(drift>.08 && failures.length<50) failures.add('${entry.key}/$i/$key: $drift');
        }
      }
    }
    expect(failures,isEmpty);
  });

  testWidgets('cat cow breathing and short foot change the rendered anatomy not only captions', (tester) async {
    final unchanged=<String>[];
    for(final name in ['Gato-camello','Respiración 90/90','Pie corto']) {
      // Remove head-only motion: the torso/foot itself must visibly change.
      final fixture=jsonDecode(jsonEncode(data)) as Map<String,Object?>;
      final raw=(fixture['figures'] as List).cast<Map<String,Object?>>().firstWhere((f)=>f['name']==name);
      for(final frame in (raw['frames'] as List).cast<Map<String,Object?>>()) { frame['gaze']=0; }
      final fig=Figure3DCatalog.fromJsonString(jsonEncode(fixture)).forExercise(name)!;
      final images=<List<int>>[];
      await tester.runAsync(() async {
        for(final progress in [0.0,1.0/fig.motion.length]) {
          final recorder=ui.PictureRecorder();
          final canvas=ui.Canvas(recorder);
          paintFigure3D(canvas,const ui.Size(420,360),fig,progress,yaw:fig.initialYaw,pitch:fig.initialPitch);
          final picture=recorder.endRecording();
          final image=await picture.toImage(420,360);
          images.add((await image.toByteData(format:ui.ImageByteFormat.rawRgba))!.buffer.asUint8List());
          image.dispose();picture.dispose();
        }
      });
      var changed=0;
      for(var i=0;i<images[0].length;i++) { if(images[0][i]!=images[1][i]) changed++; }
      if(changed<100) unchanged.add('$name: $changed changed channels');
    }
    expect(unchanged,isEmpty);
  });
}
