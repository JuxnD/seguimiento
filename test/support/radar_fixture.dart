import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/progress_metrics.dart';

final radarDay = DateTime(2026, 10, 10);
List<TestResult> radarTests() => [
      for (final (id, a, b) in [
        ('pullup', 5.0, 8.0),
        ('pushup', 15.0, 20.0),
        ('hollow_hold', 25.0, 35.0),
        ('broad_jump', 165.0, 180.0)
      ])
        for (final (round, value, day) in [(1, a, 1), (2, b, 9)])
          TestResult(
              round: round,
              item: id,
              value: value,
              date: DateTime(2026, 10, day)),
      for (final (round, value, day) in [(1, 16.0, 1), (2, 20.0, 9)])
        for (final side in ['I', 'D'])
          TestResult(
              round: round,
              item: 'bulgarian_split_squat',
              side: side,
              value: value + (side == 'D' ? 2 : 0),
              date: DateTime(2026, 10, day))
    ];
Map<RadarAxis, RadarReference> radarReferences({double pull = 10}) => {
      for (final (axis, value) in [
        (RadarAxis.pull, pull),
        (RadarAxis.push, 30.0),
        (RadarAxis.core, 45.0),
        (RadarAxis.legs, 25.0),
        (RadarAxis.jump, 200.0),
        (RadarAxis.circuit, 10.0)
      ])
        axis: RadarReference(
            id: 'fixture-${axis.name}',
            axis: axis,
            value: value,
            unit: axis.unit,
            from: DateTime(2026, 10, 1),
            source: 'Referencia FICTICIA aceptada')
    };
CindyObservation radarCindy(
        {String id = 's1',
        int day = 9,
        int rounds = 8,
        int? extra = 15,
        int total = 1500,
        int warmup = 180,
        int cooldown = 120,
        bool imported = false,
        bool estimated = false,
        bool incomplete = false,
        String? mode = 'cindy',
        List<CindySet>? sets,
        bool? technique}) =>
    CindyObservation(
        id: id,
        date: DateTime(2026, 10, day),
        type: SessionType.resistencia,
        mode: mode,
        totalSec: total,
        warmupSec: warmup,
        cooldownSec: cooldown,
        rounds: rounds,
        extraReps: extra,
        imported: imported,
        estimated: estimated,
        incomplete: incomplete,
        techniqueOk: technique,
        sets: sets ??
            [
              for (var r = 0; r < rounds; r++) ...[
                const CindySet(exercise: 'Dominadas', reps: 5),
                const CindySet(exercise: 'Flexiones', reps: 10),
                const CindySet(exercise: 'Sentadillas', reps: 15)
              ],
              if (extra != null && extra > 0)
                CindySet(exercise: 'Dominadas', reps: extra.clamp(0, 5)),
              if (extra != null && extra > 5)
                CindySet(exercise: 'Flexiones', reps: (extra - 5).clamp(0, 10)),
              if (extra != null && extra > 15)
                CindySet(exercise: 'Sentadillas', reps: extra - 15)
            ]);
