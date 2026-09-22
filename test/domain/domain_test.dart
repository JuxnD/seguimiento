import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/format.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/session_math.dart';

void main() {
  final start = DateTime(2026, 8, 26); // miércoles

  group('semana anclada al inicio', () {
    test('el día de inicio es semana 1 y la semana va de mié a mar', () {
      expect(weekIndexFor(start, start), 1);
      expect(weekIndexFor(start, DateTime(2026, 9, 1)), 1);
      expect(weekIndexFor(start, DateTime(2026, 9, 2)), 2);
      final w4 = weekRange(start, 4);
      expect(dayKey(w4.start), '2026-09-16');
      expect(dayKey(w4.end), '2026-09-22');
      expect(w4.days.length, 7);
    });

    test('fechas previas al inicio dan semana ≤ 0 sin error', () {
      expect(weekIndexFor(start, DateTime(2026, 8, 25)), 0);
      expect(weekIndexFor(start, DateTime(2026, 8, 19)), 0);
      expect(weekIndexFor(start, DateTime(2026, 8, 18)), -1);
    });
  });

  group('duraciones', () {
    test('parse y formato', () {
      expect(parseDuration('20:00'), 1200);
      expect(parseDuration('9'), 540);
      expect(parseDuration('1:02:03'), 3723);
      expect(parseDuration('x'), isNull);
      expect(parseDuration(''), isNull);
      expect(formatDuration(1200), '20:00');
      expect(formatDuration(3723), '1:02:03');
    });
  });

  group('sesión', () {
    test('circuito neto = total − cal − enf, nunca negativo', () {
      expect(circuitNetSec(totalSec: 1200, warmupSec: 540, cooldownSec: 180), 480);
      expect(circuitNetSec(totalSec: 100, warmupSec: 540, cooldownSec: 180), 0);
    });

    test('estimación de rondas por tiempo', () {
      // 20 min netos, ronda media 2:10 + 30 s de transición → 7 rondas.
      expect(estimateRounds(netSec: 1200, meanRoundSec: 130), 7); // descanso por defecto: 30 s
      expect(estimateRounds(netSec: 1200, meanRoundSec: 160, restSec: 0), 7);
      expect(estimateRounds(netSec: 0, meanRoundSec: 130), 0);
    });

    test('vueltas del contador', () {
      expect(lapDurations([150, 310, 480]), [150, 160, 170]);
      expect(meanSec([150, 160, 170]), 160);
      expect(meanSec([]), isNull);
    });
  });

  group('nutrición y unidades', () {
    test('macros por unidad y por 100 g', () {
      const huevo = Macros(kcal: 72, protein: 6.3, carbs: 0.4, fat: 4.8);
      expect(macrosFor(basis: FoodBasis.unit, perBasis: huevo, quantity: 3).kcal, closeTo(216, 1e-9));
      const arroz = Macros(kcal: 130, protein: 2.7);
      expect(macrosFor(basis: FoodBasis.per100, perBasis: arroz, quantity: 250).protein, closeTo(6.75, 1e-9));
    });

    test('pulgadas se guardan en cm', () {
      expect(toCm(10, LengthUnit.inch), closeTo(25.4, 1e-9));
      expect(fromCm(25.4, LengthUnit.inch), closeTo(10, 1e-9));
      expect(toCm(80, LengthUnit.cm), 80);
    });
  });

  group('formato es-CO', () {
    test('miles y decimales', () {
      expect(fmtInt(2150), '2.150');
      expect(fmtInt(138.4), '138');
      expect(fmtDec(82.5), '82,5');
      expect(fmtDec(80.0), '80');
      expect(fmtDec(-0.8), '-0,8');
      expect(fmtDelta(1.5), '+1,5');
      expect(fmtDelta(-0.04), '0');
      expect(mdCell('a|b\nc'), r'a\|b / c');
      expect(mdCell('  '), '—');
    });
  });
}
