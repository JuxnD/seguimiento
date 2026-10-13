import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/leg_chain.dart';

/// Cadena por grupo y motivos del Plan B (§16.24, plan 039). Fechas ficticias:
/// sáb 2 … vie 8 de marzo de 2030.
void main() {
  DateTime d(int day) => DateTime(2030, 3, day);
  ChainSession s(int day, SessionType type, {int? rpe, int? min = 40, int? rir, String? mode, Set<String> ex = const {}}) =>
      ChainSession(date: d(day), type: type, rpe: rpe, workMinutes: min, minRealRir: rir, mode: mode, exercises: ex);
  ChainSession game(int day, int min, [int intensity = 7]) =>
      ChainSession(date: d(day), rpe: intensity, workMinutes: min, isFootball: true);

  group('clasificación', () {
    test('bordes de minutos, RIR y RPE', () {
      expect(classifySession(s(4, SessionType.circuito, rpe: 7, min: 19))!.intensity, DayIntensity.moderate);
      expect(classifySession(s(4, SessionType.circuito, rpe: 7, min: 20))!.intensity, DayIntensity.intense);
      expect(classifySession(game(4, 44))!.intensity, DayIntensity.moderate);
      expect(classifySession(game(4, 45))!.intensity, DayIntensity.intense);
      expect(classifySession(s(4, SessionType.circuito, rir: 2, min: null))!.intensity, DayIntensity.intense);
      expect(classifySession(s(4, SessionType.circuito, rir: 3, min: null))!.intensity, DayIntensity.moderate);
      expect(classifySession(s(4, SessionType.circuito, rpe: 6))!.intensity, DayIntensity.moderate);
      expect(classifySession(s(4, SessionType.circuito, rpe: 5)), isNull, reason: 'RPE ≤ 5 no cuenta');
    });

    test('exclusiones antes de cualquier regla', () {
      expect(classifySession(s(4, SessionType.movilidad, rpe: 9)), isNull);
      expect(classifySession(s(4, SessionType.circuito, rpe: 9, mode: 'tecnica')), isNull);
      expect(classifySession(s(4, SessionType.otro, rpe: 9, mode: 'test')), isNull);
      expect(
          classifySession(ChainSession(date: d(4), type: SessionType.circuito, rpe: 9, workMinutes: 40, imported: true)),
          isNull);
    });

    test('sin datos para clasificar: desconocida, no se inventa', () {
      expect(classifySession(s(4, SessionType.bloques))!.intensity, DayIntensity.unknown);
      expect(classifySession(s(4, SessionType.circuito, rpe: 8, min: null))!.intensity, DayIntensity.unknown,
          reason: 'RPE 8 sin minutos medidos no prueba 20 min');
    });

    test('grupos: por ejercicios, y si no, por tipo', () {
      expect(classifySession(s(4, SessionType.trenSuperior, rpe: 8))!.groups, {ChainGroup.torso});
      expect(classifySession(s(4, SessionType.piernas, rpe: 8))!.groups, {ChainGroup.legs});
      expect(classifySession(s(4, SessionType.circuito, rpe: 8))!.groups, {ChainGroup.legs, ChainGroup.torso});
      expect(classifySession(s(4, SessionType.bloques, rpe: 8, ex: {'Dominadas'}))!.groups, {ChainGroup.torso});
      expect(classifySession(s(4, SessionType.bloques, rpe: 8))!.groups, isNull);
      expect(classifySession(game(4, 90))!.groups, {ChainGroup.legs});
    });
  });

  group('catálogo y modos (observación root 13:52)', () {
    test('los nueve de pierna del Plan v3.2 cuentan como pierna', () {
      for (final name in const [
        'Copenhague',
        'Sóleo sentado con mochila',
        'Tibial en la pared',
        'Sprint lanzado',
        'Sentadilla isométrica en la pared',
        'Abducción de cadera de lado',
        'Nórdico inverso',
        'Bajada lateral del escalón',
        'Aterrizaje clavado',
      ]) {
        expect(classifySession(s(4, SessionType.bloques, rpe: 8, ex: {name}))!.groups, {ChainGroup.legs}, reason: name);
      }
    });

    test('los nombres de torso del Plan v3.2 cuentan como torso (catálogo 034)', () {
      for (final name in const [
        'Rotación externa con banda',
        'Y-T prono',
        'Support hold en paralelas',
        'Scap pull-up',
        'Flexiones escapulares',
        'Plancha inversa con patada',
        'Mesa invertida',
        'Plancha inversa sobre antebrazos',
        'Plancha inversa sobre las manos',
        'Plancha inversa a una pierna',
        'Plancha inversa con pies elevados',
      ]) {
        final c = classifySession(s(4, SessionType.bloques, rpe: 8, ex: {name}))!;
        expect(c.groups, {ChainGroup.torso}, reason: name);
        expect(c.doubt, isFalse, reason: name);
      }
    });

    test('RIR 3–4 sin RPE es moderado; RIR 5 sin RPE ni minutos suficientes queda desconocido', () {
      expect(classifySession(s(4, SessionType.bloques, rir: 3, min: null))!.intensity, DayIntensity.moderate);
      expect(classifySession(s(4, SessionType.bloques, rir: 4, min: null))!.intensity, DayIntensity.moderate);
      expect(classifySession(s(4, SessionType.bloques, rir: 5, min: null))!.intensity, DayIntensity.unknown,
          reason: 'el contrato dice RIR 3–4; más allá no se infiere esfuerzo');
    });

    test('un nombre desconocido no se supone torso', () {
      final c = classifySession(s(4, SessionType.bloques, rpe: 8, ex: {'Ejercicio inventado'}))!;
      expect((c.groups, c.doubt), (null, true));
      expect(classifySession(s(4, SessionType.bloques, rpe: 8, ex: {'Burpees'}))!.groups, {ChainGroup.legs, ChainGroup.torso});
    });

    test('sesión mixta: lo conocido cuenta y el otro grupo queda en duda', () {
      final mixed = s(4, SessionType.bloques, rpe: 8, ex: {'Dominadas', 'Ejercicio inventado'});
      final c = classifySession(mixed)!;
      expect(c.groups, {ChainGroup.torso});
      expect(c.doubt, isTrue);
      final chains = intenseChains([mixed], d(5));
      expect(chains.torso.days, 1, reason: 'la prueba de torso no se borra');
      expect(chains.legs.days, 0);
      expect(chains.legs.unknownDays, [d(4)], reason: 'para piernas es duda, no "nada"');
    });

    test('rutinas de 032 fuera aunque el tipo histórico no sea movilidad; la normal elegida conserva su clase', () {
      for (final mode in const ['morning_activa', 'night_suelta', 'recovery_active']) {
        expect(classifySession(s(4, SessionType.otro, rpe: 8, mode: mode)), isNull, reason: mode);
      }
      // "Esto ya no fue recuperación" → guardada como `otro` con mode null.
      expect(classifySession(s(4, SessionType.otro, rpe: 7))!.intensity, DayIntensity.intense);
    });
  });

  group('cadena', () {
    test('caso del traspaso: el jueves sin nada reinicia; el viernes queda en 0', () {
      final c = intenseChains([
        game(2, 90),
        game(3, 90),
        s(4, SessionType.circuitoLigero, rpe: 7, min: 30),
        game(4, 60),
        s(5, SessionType.trenSuperior, rir: 2, min: 40),
        s(6, SessionType.circuitoLigero, rir: 3, min: 30),
      ], d(8));
      expect(c.legs.days, 0);
      expect(c.torso.days, 0);
    });

    test('moderado no suma ni rompe; desconocido se lista; torso no suma a piernas', () {
      final c = intenseChains([
        game(3, 90), // dom intenso
        s(4, SessionType.circuitoLigero, rir: 3), // lun moderado
        s(5, SessionType.bloques, rpe: 8), // mar desconocido (sin grupo)
        s(6, SessionType.piernas, rpe: 8), // mié intenso
        s(7, SessionType.trenSuperior, rpe: 8), // jue torso: piernas sin nada → reinicia
      ], d(8)); // el viernes, con el jueves ya cerrado
      expect(c.legs.days, 0, reason: 'el jueves sólo hubo torso');
      expect(c.torso.days, 1);
      final wed = intenseChains([
        game(3, 90),
        s(4, SessionType.circuitoLigero, rir: 3),
        s(5, SessionType.bloques, rpe: 8),
        s(6, SessionType.piernas, rpe: 8),
      ], d(6));
      expect(wed.legs.days, 2);
      expect(wed.legs.moderateDays, [d(4)]);
      expect(wed.legs.unknownDays, [d(5)]);
      expect(wed.legs.evidenceText, 'dom 3 mar fútbol 90 min · mié 6 mar piernas RPE 8');
    });

    test('hoy sin sesión no corta: se cuenta hasta ayer', () {
      final c = intenseChains([game(3, 90), game(4, 90), game(5, 90)], d(6));
      expect(c.legs.days, 3);
    });
  });

  group('Plan B', () {
    final three = intenseChains([game(3, 90), game(4, 90), game(5, 90)], d(6)).legs;

    test('cadena 3 en día de piernas: motivo con los días', () {
      final a = planBAdvice(dayHasLegs: true, legs: three);
      expect(a.show, isTrue);
      expect(a.reasons.single.$2,
          'Piernas: 3 días intensos (dom 3 mar fútbol 90 min · lun 4 mar fútbol 90 min · mar 5 mar fútbol 90 min)');
      expect(a.nightHrEvaluable, isFalse);
    });

    test('día sin pierna o rojo de 032: nada', () {
      expect(planBAdvice(dayHasLegs: false, legs: three).show, isFalse);
      expect(planBAdvice(dayHasLegs: true, legs: three, restOnly: true).show, isFalse);
    });

    test('la mañana verde suprime sólo la cadena', () {
      final a = planBAdvice(dayHasLegs: true, legs: three, greenMorning: true);
      expect((a.show, a.chainSuppressedByGreenMorning), (false, true));
      final knee = planBAdvice(dayHasLegs: true, legs: three, greenMorning: true, kneeStairs: 4, kneeStairsDate: d(6));
      expect(knee.show, isTrue);
      expect(knee.reasons.map((r) => r.$1), [PlanBReason.kneeStairs]);
      expect(knee.reasons.single.$2, 'Rodilla en escaleras 4/10 (mié 6 mar)');
    });

    test('escaleras: 3 no, 4 sí; null no es verde ni 0', () {
      final none = intenseChains(const [], d(6)).legs;
      expect(planBAdvice(dayHasLegs: true, legs: none, kneeStairs: 3).show, isFalse);
      expect(planBAdvice(dayHasLegs: true, legs: none, kneeStairs: 4).show, isTrue);
      expect(planBAdvice(dayHasLegs: true, legs: none).show, isFalse);
    });

    test('otra zona de pierna conserva su texto', () {
      final none = intenseChains(const [], d(6)).legs;
      final a = planBAdvice(dayHasLegs: true, legs: none, legSoreness: {'Isquios': (5, d(5))});
      expect(a.reasons.single, (PlanBReason.legSoreness, 'Molestia en Isquios 5/10 (mar 5 mar)'));
    });

    test('informe: la misma cadena', () {
      final lines = legChainReportLines(three, GroupChain.empty);
      expect(lines.first, startsWith('Piernas: 3 días intensos al cierre (dom 3 mar fútbol 90 min'));
      expect(lines.last, 'Pulso de la noche: no evaluable (sin fuente nocturna)');
      expect(legChainReportLines(GroupChain.empty, GroupChain.empty), isEmpty);
    });
  });
}
