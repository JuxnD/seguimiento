import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/habits.dart';
import 'package:seguimiento/domain/sleep_entry.dart';

/// Plan 040: noche con hora de acostarse y de despertar, procedencia del dato
/// y sudor sólo con agua conocida y pesajes comparables.
void main() {
  final mon = DateTime(2030, 3, 4);

  group('noche', () {
    test('acostarse antes de medianoche cruza al día anterior', () {
      final w = sleepWindow(mon, (23, 38), (11, 0));
      expect(w.start, DateTime(2030, 3, 3, 23, 38));
      expect(w.wake, DateTime(2030, 3, 4, 11));
      expect(hoursBetween(w.start, w.wake), closeTo(11.37, 0.01));
    });

    test('acostarse de madrugada queda el mismo día', () {
      final w = sleepWindow(mon, (1, 15), (8, 45));
      expect(w.start, DateTime(2030, 3, 4, 1, 15));
      expect(hoursBetween(w.start, w.wake), 7.5);
    });

    test('igual hora de acostarse y despertar es una noche de 24 h: se rechaza', () {
      final w = sleepWindow(mon, (7, 0), (7, 0));
      expect(w.start, DateTime(2030, 3, 3, 7));
      expect(hoursBetween(w.start, w.wake), isNull, reason: 'pasa de 16 h');
    });

    test('despertar antes de acostarse no da horas', () {
      expect(hoursBetween(DateTime(2030, 3, 4, 8), DateTime(2030, 3, 4, 7)), isNull);
      expect(hoursBetween(DateTime(2030, 3, 4, 8), DateTime(2030, 3, 4, 8)), isNull);
    });

    test('procedencia tras editar a mano', () {
      expect(sleepSourceAfterEdit(null, fromClock: false), sleepSourceManual);
      expect(sleepSourceAfterEdit(sleepSourceManual, fromClock: false), sleepSourceManual);
      expect(sleepSourceAfterEdit(sleepSourceClock, fromClock: false), sleepSourceEditManual,
          reason: 'lo del reloj corregido a mano no se presenta como del reloj');
      expect(sleepSourceAfterEdit(sleepSourceEditManual, fromClock: false), sleepSourceEditManual);
      expect(sleepSourceAfterEdit(null, fromClock: true), sleepSourceClock);
      expect(sleepSourceLabel(null), isNull);
      expect(sleepSourceLabel(sleepSourceManual), isNull);
      expect(sleepSourceLabel(sleepSourceClock), 'anotado del reloj');
    });
  });

  group('sudor', () {
    test('sólo con agua conocida y pesajes confirmados comparables', () {
      final ok = sweatReading(beforeKg: 80.4, afterKg: 79.4, fluidMl: 500, minutes: 90, weightsComparable: true)!;
      expect(ok.lossKg, closeTo(1, 1e-9));
      expect(ok.ratePerHourL, closeTo(1, 1e-9));
      expect(ok.replaceL, closeTo(1.5, 1e-9));
      expect(sweatReading(beforeKg: 80, afterKg: 79, fluidMl: 0, minutes: 60, weightsComparable: true), isNotNull,
          reason: 'un 0 anotado sí es un dato');
      expect(sweatReading(beforeKg: 80, afterKg: 79, fluidMl: null, minutes: 60, weightsComparable: true), isNull);
      expect(sweatReading(beforeKg: 80, afterKg: 79, fluidMl: 500, minutes: 60, weightsComparable: false), isNull,
          reason: 'después de comer o medición alterada');
      expect(sweatReading(beforeKg: 80, afterKg: 79, fluidMl: 500, minutes: 60), isNull,
          reason: 'sin confirmar (o de antes) tampoco es válido');
      expect(sweatReading(beforeKg: double.nan, afterKg: 79, fluidMl: 0, minutes: 60, weightsComparable: true), isNull);
      expect(sweatReading(beforeKg: 80, afterKg: 79, fluidMl: -1, minutes: 60, weightsComparable: true), isNull);
    });
  });
}
