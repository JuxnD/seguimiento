import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/energy.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/report/period_summary.dart';
import 'package:seguimiento/domain/report/report_input.dart';

DateTime d(int month, int day) => DateTime(2026, month, day);

/// Circuito de 8 rondas: 5 dominadas, 10 flexiones y 15 sentadillas por ronda.
SessionEntry circuit(DateTime date, {int rounds = 8}) => SessionEntry(
      date: date,
      type: SessionType.progresion,
      totalSec: 1200,
      warmupSec: 360,
      cooldownSec: 180,
      restSec: 210,
      roundsDone: rounds,
      sets: [
        for (var r = 1; r <= rounds; r++) ...[
          SetEntry(exercise: 'Dominadas', setIndex: r, reps: 5),
          SetEntry(exercise: 'Flexiones', setIndex: r, reps: 10),
          SetEntry(exercise: 'Sentadillas', setIndex: r, reps: 15),
        ],
      ],
    );

void main() {
  final previousWeek = ReportInput(
    programStart: d(8, 26),
    rangeStart: d(9, 23),
    rangeEnd: d(9, 29),
    today: d(10, 2),
    sessions: [circuit(d(9, 25), rounds: 7)],
    steps: {d(9, 24): 4000},
    baselineWeight: WeightEntry(date: d(9, 18), kg: 70, fasted: true),
  );

  final week = ReportInput(
    programStart: d(8, 26),
    rangeStart: d(9, 30),
    rangeEnd: d(10, 6),
    today: d(10, 2),
    sessions: [
      circuit(d(9, 30), rounds: 5),
      circuit(d(10, 2), rounds: 9),
      SessionEntry(
        date: d(10, 1),
        type: SessionType.bloques,
        totalSec: 1500,
        sets: const [
          SetEntry(exercise: 'Plancha lateral', setIndex: 1, reps: 40),
          SetEntry(exercise: 'Plancha lateral', setIndex: 2, reps: 40),
        ],
      ),
    ],
    football: [FootballEntry(date: d(10, 4), format: 8, minutes: 60)],
    steps: {d(9, 30): 8000, d(10, 1): 6000, d(10, 4): 12000},
    weightsInRange: [WeightEntry(date: d(10, 2), kg: 72, fasted: true)],
    baselineWeight: WeightEntry(date: d(9, 18), kg: 70, fasted: true),
    mobility: [MobilityEntry(date: d(10, 1), totalSec: 600)],
    holdExercises: {'Plancha lateral'},
    previous: previousWeek,
  );

  test('cuenta las repeticiones de cada ejercicio de la semana', () {
    final s = summarizePeriod(week);
    expect(s.repsOf('Dominadas'), 5 * 14, reason: '5 + 9 rondas de 5');
    expect(s.repsOf('Flexiones'), 10 * 14);
    expect(s.repsOf('Sentadillas'), 15 * 14);
    expect(s.totalReps, 30 * 14, reason: 'la plancha va en segundos, no suma repeticiones');
    expect(s.exercises.first.name, 'Sentadillas', reason: 'lo que más se repite, arriba');
    expect(s.exercises.last.isHold, isTrue, reason: 'los aguantes van al final');
    expect(s.maxRounds, 9);
  });

  test('compara cada ejercicio contra la semana anterior', () {
    final s = summarizePeriod(week);
    final flexiones = s.exercises.firstWhere((e) => e.name == 'Flexiones');
    expect(flexiones.previous, 70);
    expect(flexiones.delta, 70);
    final plancha = s.exercises.firstWhere((e) => e.name == 'Plancha lateral');
    expect(plancha.previous, 0, reason: 'no se hizo la semana anterior');
  });

  test('suma pasos, kilómetros y el mejor día', () {
    final s = summarizePeriod(week, heightCm: 180);
    expect(s.stepsTotal, 26000);
    expect(s.stepsDays, 3);
    expect(s.bestStepsDay, (d(10, 4), 12000));
    expect(s.weekdaysWithSteps, 2, reason: 'el domingo no tiene meta');
    expect(s.weekdaysAtGoal, 1);
    expect(s.distanceKm, closeTo(26000 * 0.747 / 1000, 0.01));
  });

  test('el gasto suma entrenamiento, fútbol y caminar sin contar dos veces el partido', () {
    final s = summarizePeriod(week);
    expect(s.weightKg, 72, reason: 'el último peso del rango');
    expect(s.kcalFootball, closeTo(7.0 * 72 * 1, 0.01));
    // El domingo de partido sus 12.000 pasos no entran: solo 8.000 + 6.000.
    expect(s.kcalSteps, closeTo(stepsKcal(14000, weightKg: 72)!, 0.01));
    expect(s.kcalTraining, greaterThan(0));
    expect(s.kcalBurned, closeTo(s.kcalTraining! + s.kcalFootball! + s.kcalSteps!, 0.01));
  });

  test('sin peso no inventa el gasto', () {
    final s = summarizePeriod(ReportInput(
      programStart: d(8, 26),
      rangeStart: d(9, 30),
      rangeEnd: d(10, 6),
      today: d(10, 2),
      sessions: [circuit(d(9, 30))],
    ));
    expect(s.kcalBurned, isNull);
    expect(s.totalReps, 240);
  });

  test('tiempo activo: sesiones, movilidad y fútbol', () {
    final s = summarizePeriod(week);
    expect(s.trainingSec, 1200 + 1200 + 1500 + 600);
    expect(s.activeSec, s.trainingSec + 60 * 60);
    expect(s.mobilitySessions, 1);
    expect(s.footballGames, 1);
    expect(s.previous!.totalReps, 7 * 30);
  });

  test('un periodo vacío lo dice', () {
    final s = summarizePeriod(ReportInput(programStart: d(8, 26), rangeStart: d(9, 30), rangeEnd: d(10, 6), today: d(10, 2)));
    expect(s.isEmpty, isTrue);
    expect(s.stepsAvg, isNull);
  });
}
