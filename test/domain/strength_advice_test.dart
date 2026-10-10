import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/adaptive_coach.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/progress_evidence.dart';

/// Plan 009 sobre la evidencia de 008: qué subir hoy y, si no, por qué.
void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);
  final today = d(10, 20);

  StrengthSessionEvidence ev(List<StrengthSetEvidence> sets,
          {String? mode, bool incomplete = false, bool imported = false, int? planDayId = 7}) =>
      StrengthSessionEvidence(
        sessionId: 1,
        date: d(10, 13),
        type: SessionType.trenSuperior,
        exercise: 'Fondos en barra',
        sets: sets,
        planDayId: planDayId,
        mode: mode,
        incomplete: incomplete,
        imported: imported,
      );
  List<StrengthSetEvidence> clean([int reps = 10]) =>
      [for (var i = 0; i < 4; i++) StrengthSetEvidence(reps: reps, rir: 2)];

  StrengthAdvice advise(StrengthSessionEvidence? e, {bool perSide = false, String? mode}) => strengthAdvice(
        exercise: 'Fondos en barra',
        evidence: e,
        date: today,
        repsMin: 6,
        repsMax: 10,
        plannedSets: 4,
        perSide: perSide,
        planDayId: 7,
        mode: mode,
        tracksLoad: true,
      );

  test('limpio y al tope: sube con la regla existente', () {
    final a = advise(ev(clean()));
    expect((a.status, a.text), (StrengthStatus.subir, '+2–5 kg de mochila y vuelve a 6'));
  });

  test('cada causa de no subir sale de lo guardado', () {
    final cases = {
      'llegaste al fallo': ev([...clean().take(3), const StrengthSetEvidence(reps: 10, rir: 1, toFailure: true)]),
      'serie partida (8+2)': ev([...clean().take(3), const StrengthSetEvidence(reps: 10, split: true, splitDetail: '8+2')]),
      'RIR 0': ev([...clean().take(3), const StrengthSetEvidence(reps: 10, rir: 0)]),
      'quedó incompleta': ev(clean(), incomplete: true),
      'historial importado': ev(clean(), imported: true),
      'sesión técnica': ev(clean(), mode: 'tecnica'),
      'mezclaste variante o carga': ev([...clean().take(3), const StrengthSetEvidence(reps: 10, rir: 2, loadKg: 5)]),
      'la más baja: 8': ev([...clean().take(3), const StrengthSetEvidence(reps: 8, rir: 2)]),
      'otro día del plan': ev(clean(), planDayId: 9),
    };
    for (final e in cases.entries) {
      final a = advise(e.value);
      expect(a.status, StrengthStatus.mantener, reason: e.key);
      expect(a.text, contains(e.key), reason: e.key);
    }
  });

  test('por lado no se compara: lo guardado no conserva el lado', () {
    final a = advise(ev(clean()), perSide: true);
    expect((a.status, a.text.contains('por lado')), (StrengthStatus.mantener, true));
  });

  test('sin registro anterior lo dice, no inventa', () {
    expect(advise(null).status, StrengthStatus.sinDatos);
  });

  group('revisión con la dosis guardada (R2)', () {
    StrengthSessionEvidence later(List<StrengthSetEvidence> sets, {String? mode, int? planDayId = 7}) =>
        StrengthSessionEvidence(
            sessionId: 2,
            date: d(10, 20),
            type: SessionType.trenSuperior,
            exercise: 'Remo invertido',
            sets: sets,
            planDayId: planDayId,
            mode: mode);
    final chain = ['Remo con rodillas dobladas', 'Remo con piernas rectas', 'Remo con pies elevados'];
    StrengthDose variantDose() => strengthDose(
        evidence: StrengthSessionEvidence(
            sessionId: 1,
            date: d(10, 13),
            type: SessionType.trenSuperior,
            exercise: 'Remo invertido',
            planDayId: 7,
            sets: [for (var i = 0; i < 3; i++) const StrengthSetEvidence(reps: 12, rir: 2, variant: 'Remo con piernas rectas')]),
        repsMin: 8,
        plannedSets: 3,
        chain: chain,
        planDayId: 7);

    test('variante: la siguiente de la cadena, guardada y leída de vuelta sin texto', () {
      final dose = StrengthDose.decode(variantDose().encode())!;
      expect((dose.kind, dose.fromVariant, dose.toVariant, dose.sets), (DoseKind.variante, 'Remo con piernas rectas', 'Remo con pies elevados', 3));
      List<StrengthSetEvidence> at(String v, {int n = 3}) => [for (var i = 0; i < n; i++) StrengthSetEvidence(reps: 9, rir: 2, variant: v)];
      expect(strengthReview(dose, later(at('Remo con pies elevados'))), 'subiste a Remo con pies elevados y se sostuvo el 20 oct (3 series limpias)');
      expect(strengthReview(dose, later(at('Remo con piernas rectas'))), 'aceptaste subir; el 20 oct repetiste Remo con piernas rectas: no demuestra la subida');
      expect(strengthReview(dose, later(at('Remo con pies elevados', n: 2))),
          'aceptaste subir a Remo con pies elevados; el 20 oct sólo 2 de 3 series con la subida: no demostrada');
      expect(strengthReview(dose, later(at('Remo con pies elevados'), planDayId: 9)),
          'aceptaste subir; el 20 oct fue otro día del plan: no demuestra la subida');
    });

    test('banda o pausa: no se registran, así que no se afirma la subida', () {
      final dose = strengthDose(evidence: ev(clean()), repsMin: 6, plannedSets: 4, planDayId: 7);
      expect(dose.kind, DoseKind.otra);
      expect(strengthReview(dose, later(clean(8))), startsWith('aceptaste subir (más banda o pausa arriba)'));
    });

    test('lo guardado que no es una dosis no se interpreta', () {
      expect(StrengthDose.decode('+2–5 kg de mochila y vuelve a 6'), isNull);
      expect(StrengthDose.decode('{"v":2}'), isNull);
      expect(StrengthDose.decode(null), isNull);
    });
  });
}
