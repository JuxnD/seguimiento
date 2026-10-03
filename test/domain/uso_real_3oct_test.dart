import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/domain/report/report_input.dart';
import 'package:seguimiento/domain/report/report_stats.dart';
import 'package:seguimiento/domain/session_math.dart';

/// Lo que salió del traspaso del 3 oct (§16.9).
void main() {
  // Sesión del 2 oct: R3 de 1:28 tras un descanso de 0:00; el resto 0:46–0:54.
  const work = [50, 52, 88, 51, 54, 49, 53, 46, 52];
  const rests = [30, 0, 30, 30, 30, 30, 30, 30, 0];

  group('descanso de 0:00 que infla la ronda siguiente', () {
    test('marca R3 y nada más', () {
      expect(suspectRounds(work, rests), [2]);
    });

    test('propone pasar 30 s al descanso, sin dejar la ronda bajo la mediana', () {
      expect(reassignableSec(work, 2), 30);
      // Un exceso menor que el descanso del plan: solo se pasa el exceso.
      expect(reassignableSec([50, 50, 70, 50], 2), 20);
    });

    test('un descanso corto con una ronda normal no es sospechoso', () {
      expect(suspectRounds([50, 52, 55, 51], [30, 2, 30, 0]), isEmpty);
    });

    test('con pocas rondas no hay mediana fiable', () {
      expect(suspectRounds([50, 90], [0, 0]), isEmpty);
    });
  });

  test('el informe marca la ronda y la deja fuera de la media y del R1→Rn', () {
    final md = buildReport(ReportInput(
      programStart: DateTime(2026, 8, 26),
      rangeStart: DateTime(2026, 9, 30),
      rangeEnd: DateTime(2026, 10, 6),
      today: DateTime(2026, 10, 3),
      sessions: [
        SessionEntry(
          date: DateTime(2026, 10, 2),
          type: SessionType.progresion,
          totalSec: 1332,
          roundsDone: 9,
          roundWorkSec: work,
          roundRestSec: rests,
          pendingReview: true,
        ),
      ],
    ));
    expect(md, contains('1:28 ⚠'));
    // Media de las 8 válidas: (50+52+51+54+49+53+46+52)/8 = 50,875 → 0:51.
    expect(md, contains('media 0:51'));
    expect(md, contains('⚠ R3 fuera de la media'));
    expect(md, contains('⚠ sin revisar'), reason: 'la sesión sin RPE se ve en la tabla');
  });

  test('semana en curso: el volumen se compara con el mismo punto de la anterior (§16.8)', () {
    SessionEntry pushups(DateTime d, int reps) => SessionEntry(
        date: d, type: SessionType.circuito, sets: [SetEntry(exercise: 'Flexiones', setIndex: 1, reps: reps)]);
    final previous = ReportInput(
      programStart: DateTime(2026, 8, 26),
      rangeStart: DateTime(2026, 9, 21),
      rangeEnd: DateTime(2026, 9, 27),
      today: DateTime(2026, 10, 3),
      sessions: [pushups(DateTime(2026, 9, 21), 30), pushups(DateTime(2026, 9, 25), 80)],
    );
    final week = ReportInput(
      programStart: DateTime(2026, 8, 26),
      rangeStart: DateTime(2026, 9, 28),
      rangeEnd: DateTime(2026, 10, 4),
      today: DateTime(2026, 9, 28),
      sessions: [pushups(DateTime(2026, 9, 28), 30)],
      previous: previous,
    );
    final s = ReportStats(week);
    expect(s.inProgress, isTrue);
    expect(s.previous!.volumeFirstDays(s.elapsedCount), {'Flexiones': 30}, reason: 'solo el lunes anterior');
    final md = buildReport(week);
    expect(md, contains('Anterior, mismo punto'));
    expect(md, contains('| Flexiones | 30 | 30 | 0 |'));
  });

  test('medidas: después de comer contra ayunas se marca, y sale el índice hombros ÷ cintura (§16.10)', () {
    MeasurementEntry m(int month, int day, MeasureSite site, double cm, {bool fasted = true}) =>
        MeasurementEntry(date: DateTime(2026, month, day), site: site, valueCm: cm, fasted: fasted);
    final md = buildReport(ReportInput(
      programStart: DateTime(2026, 8, 26),
      rangeStart: DateTime(2026, 9, 28),
      rangeEnd: DateTime(2026, 10, 4),
      today: DateTime(2026, 10, 4),
      measurementsInRange: [
        m(10, 3, MeasureSite.abdomen, 91.44),
        m(10, 3, MeasureSite.cinturaEstrecha, 88.9),
        m(10, 3, MeasureSite.hombros, 124.5),
      ],
      // Única referencia previa: la del 18 sep, después de cenar.
      baselineMeasurements: {MeasureSite.abdomen: m(9, 18, MeasureSite.abdomen, 92.0, fasted: false)},
    ));
    expect(md, contains('(condiciones distintas)'));
    expect(md, contains('Índice hombros ÷ cintura: 1,4 (referencia estética ≈ 1,6)'));
  });
}
