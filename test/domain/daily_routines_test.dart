import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/daily_routines.dart';
import 'package:seguimiento/domain/mobility.dart';

/// Rutinas diarias (§19.14, §19.15) y recuperación activa (§19.17).
void main() {
  List<String?> ids(MobilityRoutine r) => [for (final e in r.exercises) e.id];

  test('Activa: los 10 del traspaso, en orden, y la versión de 4 min', () {
    expect(ids(morningActiva()), [
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
    ]);
    expect(ids(morningActiva(short: true)), ['breathing_90_90', 'wrist_rocks', 'worlds_greatest', 'knee_to_wall']);
    expect(morningActiva(short: true).id, morningActivaId, reason: 'la versión corta se guarda como la misma rutina');
  });

  test('Suelta: 8 ejercicios; el módulo de piernas va antes de piernas en la pared', () {
    expect(ids(nightSuelta()), [
      'pike_stretch',
      'pancake_stretch',
      'hip_flexor_kneel',
      'lat_stretch_bed',
      'pec_doorway',
      'figure_four',
      'soleus_wall',
      'legs_up_wall',
    ]);
    final legs = ids(nightSuelta(withLegs: true));
    expect(legs, hasLength(11));
    expect(legs.sublist(7), ['knees_to_chest', 'quad_side_lying', 'calf_wall', 'legs_up_wall']);
  });

  test('noche de partido: pike y pancake suaves y sin pulsos', () {
    final r = nightSuelta(matchNight: true);
    final cues = [...r.exercises[0].formCues, ...r.exercises[1].formCues].join(' ');
    expect(cues, contains('4/10'));
    expect(cues, isNot(contains('10 pulsos')));
    expect(nightSuelta().exercises[0].formCues.join(' '), contains('10 pulsos'));
  });

  test('recuperación activa: Activa + 2 vueltas de activación con descanso + Suelta con piernas', () {
    final r = recoveryActive();
    final all = ids(r);
    expect(all.take(10), ids(morningActiva()));
    final b = [for (final e in recoveryActivation) e.id];
    expect(b, ['scap_pushup', 'scap_pullup', 'prone_y_t', 'side_lying_hip_abduction', 'hollow_body_hold']);
    expect(all.sublist(10, 21), [...b, 'rest', ...b]);
    expect(all.sublist(21), ids(nightSuelta(withLegs: true)));
    expect(r.exercises[15].durationSec, recoveryRoundRestSec);
    expect(r.closingNote, contains('caminata'));
    // ~30 min, como dice el traspaso.
    final min = estimatedMobilitySec(buildMobilityScript(r)) / 60;
    expect(min, inInclusiveRange(22, 38));
  });

  test('cada ejercicio dice para qué sirve y cómo se hace', () {
    for (final r in [morningActiva(), nightSuelta(withLegs: true), recoveryActive()]) {
      for (final e in r.exercises) {
        expect(e.purpose, isNotNull, reason: e.name);
        expect(e.formCues, isNotEmpty, reason: e.name);
      }
    }
  });

  test('solo la recuperación activa mantiene la racha de constancia', () {
    expect(keepsConstancyStreak(recoveryActiveId), isTrue);
    expect(keepsConstancyStreak(morningActivaId), isFalse);
    expect(keepsConstancyStreak(nightSueltaId), isFalse);
    expect(keepsConstancyStreak(null), isFalse);
  });
}
