import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/habits.dart';

/// Plan 040: agua desconocida no es 0. Sin lo bebido, no hay tasa de sudor ni
/// cuánto reponer; un 0 anotado sí es un dato.
void main() {
  // Compila contra la base 25 (sin `weightsComparable`) para conservar el
  // rojo de r1-01. El caso "0 explícito sí da lectura" exige ahora pesajes
  // confirmados comparables y vive en sleep_window_test (grupo sudor).
  test('sin agua anotada no hay lectura', () {
    expect(sweatReading(beforeKg: 80, afterKg: 79, fluidMl: null, minutes: 60), isNull,
        reason: 'fluidMl ?? 0 inventaba una tasa de sudor');
  });
}
