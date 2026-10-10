import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';

void main() {
  Map<String, Object?> frame(double rise) => {
        'caption': rise == 0 ? 'Cuelga con brazos rectos' : 'Baja hombros: torso sube',
        'hip': [0, -30 - rise],
        'torso': -90,
        'gaze': 0,
        if (rise != 0) 'shoulderOffset': [0, -rise],
        'limbs': {
          for (final side in ['near', 'far'])
            '${side}Arm': {
              'angles': [-90, -90],
              'hand': -90,
              'grip': 'bar'
            },
          for (final side in ['near', 'far'])
            '${side}Leg': {
              'angles': [90, 90],
              'foot': 0
            },
        },
      };
  Figure3D fixture({bool shifted = true}) => Figure3DCatalog.fromJsonString(jsonEncode({
        'consts': {'T': 18, 'UA': 10, 'FA': 9, 'TH': 14, 'SH': 14, 'FT': 5, 'HEAD_OFF': 5.5, 'HEAD_R': 3.6},
        'figures': [
          {
            'name': 'Scapular fixture',
            'muscles': '',
            'props': [
              {'type': 'bar', 'x': 0, 'y': -67}
            ],
            'gripZ': 5,
            'continuous': true,
            'frames': [frame(0), frame(1.2)..remove(shifted ? '_absent' : 'shoulderOffset'), frame(0)]
          }
        ]
      })).forExercise('Scapular fixture')!;

  test('torso sube sin mover manos ni doblar codos en los 61 puntos del recorrido', () {
    final figure = fixture();
    expect(figure.skeletonAt(.5).joints['neck']!.dy, closeTo(-49.2, .001));
    for (var sample = 0; sample <= 60; sample++) {
      final skeleton = figure.skeletonAt(sample / 60);
      final body = liftSkeleton(skeleton, figure);
      for (final side in ['near', 'far']) {
        expect(skeleton.joints['${side}Hand']!.dy, closeTo(-67, .01), reason: '2D/${sample / 60}');
        expect(body.p['${side}Hand']!.y, closeTo(-67, .01), reason: '3D/${sample / 60}');
        final upper = (body.p['${side}Elbow']! - body.p['${side}Shoulder']!).unit;
        final lower = (body.p['${side}Hand']! - body.p['${side}Elbow']!).unit;
        expect(upper.dot(lower), greaterThan(.999), reason: 'no fingir movimiento doblando codos');
      }
    }
  });

  test('mutante sin desplazamiento escapular pierde contacto: el oráculo detecta el fallo', () {
    final figure = fixture(shifted: false);
    final body = liftSkeleton(figure.skeletonAt(.5), figure);
    expect((body.p['nearHand']!.y + 67).abs(), greaterThan(1));
  });

  test('radio declarado conserva arco de pierna; el default mantiene la cuerda antigua', () {
    Figure3D arc(bool enabled) {
      final first = frame(0), last = frame(0);
      (first['limbs'] as Map)['nearLeg'] = {
        'angles': [90, 90],
        'reach3': [0, 28, 0],
        'pole': [1, 0, 0],
        'keepReachRadius': enabled,
        'end3': [1, 0, 0]
      };
      (last['limbs'] as Map)['nearLeg'] = {
        'angles': [30, 30],
        'reach3': [24.24871130596428, 14, 0],
        'pole': [1, 0, 0],
        'keepReachRadius': enabled,
        'end3': [.5, -.8660254037844386, 0]
      };
      final json = {
        'consts': {'T': 18, 'UA': 10, 'FA': 9, 'TH': 14, 'SH': 14, 'FT': 5, 'HEAD_OFF': 5.5, 'HEAD_R': 3.6},
        'figures': [
          {
            'name': 'Arc fixture',
            'muscles': '',
            'props': [],
            'frames': [first, last]
          }
        ]
      };
      return Figure3DCatalog.fromJsonString(jsonEncode(json)).forExercise('Arc fixture')!;
    }

    final constrained = arc(true), legacy = arc(false);
    expect(lerpPose(constrained, constrained.frames[0], constrained.frames[1], .5).limbs['nearLeg']!.reach3!.length,
        closeTo(28, .001));
    expect(lerpPose(legacy, legacy.frames[0], legacy.frames[1], .5).limbs['nearLeg']!.reach3!.length, lessThan(25));
  });
  test('radio opt-in maneja antipodales por plano explícito y rechaza degeneración', () {
    final fig = fixture();
    KeyPose pose(V3 reach, {V3? pole, bool enabled = true}) => KeyPose(
          caption: '',
          hip: Offset.zero,
          torso: -90,
          gaze: 0,
          limbs: {
            'nearLeg': LimbPose(upper: 90, lower: 90, end: 0, reach3: reach, pole: pole, keepReachRadius: enabled)
          },
        );
    final a = pose(const V3(0, 28, 0), pole: const V3(1, 0, 0));
    final b = pose(const V3(0, -28, 0), pole: const V3(1, 0, 0));
    V3? previous;
    for (var i = 1; i < 60; i++) {
      final reach = lerpPose(fig, a, b, i / 60).limbs['nearLeg']!.reach3!;
      expect(reach.length, closeTo(28, .0001));
      expect(reach.x.isFinite && reach.y.isFinite && reach.z.isFinite, isTrue);
      if (previous != null) expect((reach - previous).length, lessThan(1.5));
      previous = reach;
    }
    expect(lerpPose(fig, a, b, .5).limbs['nearLeg']!.reach3!.x, closeTo(28, .001));
    expect(() => lerpPose(fig, pose(const V3(0, 28, 0)), b, .5), throwsFormatException);
    expect(() => lerpPose(fig, pose(V3.zero), b, .5), throwsFormatException);
    expect(() => lerpPose(fig, a, pose(const V3(0, 28, 0), enabled: false), .5), throwsFormatException);
  });

  test('omitir radio en artefacto generado reproduce pie fuera de rango entre claves', () {
    final source = jsonDecode(File(Figure3DCatalog.asset).readAsStringSync()) as Map;
    final raw = (source['figures'] as List).cast<Map<String, Object?>>().firstWhere((f) => f['name'] == 'Balanceos de pierna');
    for (final f in (raw['frames'] as List).cast<Map<String, Object?>>()) {
      ((f['limbs'] as Map)['nearLeg'] as Map).remove('keepReachRadius');
    }
    final figure = Figure3DCatalog.fromJsonString(jsonEncode(source)).forExercise('Balanceos de pierna')!;
    final p = liftSkeleton(figure.skeletonAt(15 / 60), figure).p;
    final shin = (p['nearAnkle']! - p['nearKnee']!).unit;
    final foot = (p['nearToe']! - p['nearAnkle']!).unit;
    expect(shin.dot(foot).abs(), greaterThan(.35), reason: 'mutante real reproduce exactamente la cuerda defectuosa');
  });
}
