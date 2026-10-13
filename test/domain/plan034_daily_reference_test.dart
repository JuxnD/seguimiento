import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/exercise_details.dart';
import 'package:seguimiento/domain/daily_routines.dart';

void main() {
  test(
      'all daily movements resolve contextual purpose and physical cues in shared library reference',
      () {
    final movements = {
      for (final e in [
        ...morningActiva().exercises,
        ...nightSuelta().exercises
      ])
        e.id: e
    };
    expect(movements.keys.toSet(), {
      'breathing_90_90',
      'cat_cow',
      'open_book',
      'wrist_rocks',
      'wall_slides',
      'hip_90_90',
      'worlds_greatest',
      'knee_to_wall',
      'deep_squat_hold',
      'short_foot',
      'pike_stretch',
      'pancake_stretch',
      'hip_flexor_kneel',
      'lat_stretch_bed',
      'pec_doorway',
      'figure_four',
      'soleus_wall',
      'legs_up_wall',
    });
    for (final movement in movements.values) {
      expect(movement.purpose, isNotNull, reason: movement.name);
      expect(movement.purpose!.trim(), isNotEmpty, reason: movement.name);
      final common = mobilityReference(movement.name);
      expect(common, isNotNull, reason: movement.name);
      expect(common!.formCues, isNotEmpty, reason: movement.name);
      expect(exercisePurpose(movement.name), isNotNull, reason: movement.name);
    }
    expect(morningActiva().exercises.first.purpose, contains('Costillas'));
  });
}
