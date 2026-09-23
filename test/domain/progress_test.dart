import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/progress.dart';

void main() {
  final hoy = DateTime(2026, 9, 23); // miércoles

  int streak(List<int> daysWithSession, {Set<int> restDays = const {}}) => currentStreak(
        today: hoy,
        trainingDates: {for (final d in daysWithSession) dayKey(DateTime(2026, 9, d))},
        isRestDay: (d) => restDays.contains(d.day),
      );

  group('racha', () {
    test('cuenta días seguidos con sesión', () {
      expect(streak([23, 22, 21]), 3);
    });

    test('un día de entrenamiento sin sesión la corta', () {
      expect(streak([23, 22, 20]), 2);
    });

    test('un día de descanso no la corta ni la suma', () {
      expect(streak([23, 22, 20], restDays: {21}), 3);
    });

    test('hoy sin entrenar todavía no rompe lo de ayer', () {
      expect(streak([22, 21]), 2);
    });

    test('sin sesiones la racha es cero', () {
      expect(streak([]), 0);
    });
  });

  group('progreso hacia la meta', () {
    test('se acota entre 0 y 1', () {
      expect(goalProgress(65, 130), closeTo(0.5, 1e-9));
      expect(goalProgress(200, 130), 1);
      expect(goalProgress(0, 130), 0);
      expect(goalProgress(10, 0), 0, reason: 'sin meta no hay progreso que pintar');
    });
  });

  group('récord', () {
    test('hay que superar, no igualar', () {
      expect(isRecord(8, 7), isTrue);
      expect(isRecord(7, 7), isFalse);
      expect(isRecord(6, 7), isFalse);
    });

    test('la primera sesión con rondas ya es récord', () {
      expect(isRecord(5, null), isTrue);
      expect(isRecord(0, null), isFalse);
    });
  });

  group('series para las gráficas', () {
    test('suma lo del mismo día y ordena', () {
      final points = dailyTotals([
        (DateTime(2026, 9, 18), 20),
        (DateTime(2026, 9, 16), 30),
        (DateTime(2026, 9, 18), 5),
      ]);
      expect(points.map((p) => p.date.day), [16, 18]);
      expect(points.last.value, 25);
    });

    test('los días sin dato quedan en cero, sin inventar pendientes', () {
      final filled = fillDays(
        dailyTotals([(DateTime(2026, 9, 16), 120)]),
        DateTime(2026, 9, 16),
        DateTime(2026, 9, 19),
      );
      expect(filled.map((p) => p.value), [120, 0, 0, 0]);
      expect(filled.length, 4);
    });

    test('el máximo escala el eje sin dividir por cero', () {
      expect(seriesMax([]), 1);
      expect(seriesMax([SeriesPoint(hoy, 0)]), 1);
      expect(seriesMax([SeriesPoint(hoy, 8), SeriesPoint(hoy, 6)]), 8);
    });
  });

  group('mensaje de cierre', () {
    test('el récord manda sobre todo lo demás', () {
      final (title, body) = sessionPraise(const SessionComparison(rounds: 9, isRecord: true, previousRounds: 8));
      expect(title, '¡Récord!');
      expect(body, contains('9 rondas'));
    });

    test('subir de ronda respecto a la anterior se celebra con el dato', () {
      final (title, body) = sessionPraise(const SessionComparison(
        rounds: 6, plannedRounds: 6, previousRounds: 5, previousDateLabel: 'el lunes 21'));
      expect(title, '¡Subiste!');
      expect(body, '+1 ronda más que el lunes 21.');
    });

    test('mismas rondas pero más rápido', () {
      final (title, body) = sessionPraise(const SessionComparison(
        rounds: 5, previousRounds: 5, meanLapSec: 78, previousMeanLapSec: 84));
      expect(title, 'Más rápido');
      expect(body, contains('6 s menos'));
    });

    test('una diferencia de 1 s no se vende como mejora', () {
      final (title, _) = sessionPraise(const SessionComparison(
        rounds: 5, plannedRounds: 5, previousRounds: 5, meanLapSec: 83, previousMeanLapSec: 84));
      expect(title, 'Plan cumplido');
    });

    test('incompleta: registrada, sin culpa y con el dato', () {
      final (title, body) = sessionPraise(const SessionComparison(rounds: 7, plannedRounds: 8, incomplete: true));
      expect(title, 'Sesión registrada');
      expect(body, startsWith('7 de 8 rondas'));
    });

    test('una sola ronda se dice en singular', () {
      final (_, body) = sessionPraise(const SessionComparison(rounds: 1, plannedRounds: 1));
      expect(body, startsWith('1 de 1 ronda.'));
    });

    test('sin comparación posible, igual cierra en positivo', () {
      expect(sessionPraise(const SessionComparison(rounds: null)).$1, 'Sesión completa');
    });
  });
}
