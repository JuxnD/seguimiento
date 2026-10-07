import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/report/period_summary.dart';
import 'package:seguimiento/domain/report/report_input.dart';

/// Denominador justo del resumen de Progreso (§16.16).
void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);
  final weekdays = PlanVersionInfo(number: 1, validFrom: d(8, 1), dayTypes: {
    for (var w = 1; w <= 5; w++) w: DayType.circuito,
  });

  test('mes en curso: los días hábiles hasta hoy, no los del mes entero', () {
    final s = summarizePeriod(ReportInput(
      programStart: d(8, 26),
      rangeStart: d(10, 1),
      rangeEnd: d(10, 31),
      today: d(10, 6),
      dataStart: d(8, 26),
      planVersions: [weekdays],
    ));
    expect(s.plannedSessions, 22, reason: 'octubre trae 22 días hábiles');
    expect(s.plannedElapsed, 4, reason: 'jue 1, vie 2, lun 5 y mar 6');
    expect(s.plannedWithoutData, 0);
  });

  test('los días antes del primer dato en la app no son faltas', () {
    final s = summarizePeriod(ReportInput(
      programStart: d(8, 26),
      rangeStart: d(8, 1),
      rangeEnd: d(8, 31),
      today: d(10, 6),
      dataStart: d(8, 26),
      planVersions: [weekdays],
    ));
    expect(s.plannedSessions, 21);
    expect(s.plannedWithoutData, 17, reason: 'del 3 al 25 de agosto no hay datos en la app');
    expect(s.plannedSessions - s.plannedWithoutData, 4, reason: '26, 27, 28 y 31');
  });

  test('una sesión importada suma a totales pero no es marca', () {
    SessionEntry circuit(DateTime date, int rounds, {bool imported = false}) => SessionEntry(
          date: date,
          type: SessionType.progresion,
          roundsDone: rounds,
          imported: imported,
          sets: [
            for (var r = 1; r <= rounds; r++) SetEntry(exercise: 'Dominadas', setIndex: r, reps: 5),
          ],
        );
    final s = summarizePeriod(ReportInput(
      programStart: d(8, 26),
      rangeStart: d(9, 1),
      rangeEnd: d(9, 30),
      today: d(10, 6),
      planVersions: [weekdays],
      sessions: [circuit(d(9, 11), 7, imported: true), circuit(d(9, 25), 6)],
    ));
    expect(s.trainingSessions, 2);
    expect(s.repsOf('Dominadas'), 5 * 13);
    expect(s.maxRounds, 6, reason: 'las 7 del 11 sep vienen del historial importado');
  });
}
