import 'dates.dart';
import 'plan_v3.dart' show v31TestDate;

// Test de condición del v3.1 (§19.11): una serie máxima por prueba con
// técnica estricta, cortada en la primera repetición fea. Test 1 en la
// semana 1, Test 2 en la descarga (semana 6) y Test 3 en las pruebas de la
// semana 9.

enum TestUnit {
  reps('reps'),
  seconds('s'),
  cm('cm');

  const TestUnit(this.short);
  final String short;
}

class TestItem {
  const TestItem(this.id, this.name, this.unit, {this.perSide = false, this.hint});

  final String id;
  final String name;
  final TestUnit unit;

  /// Se registra cada lado (I y D).
  final bool perSide;
  final String? hint;

  bool get isHold => unit == TestUnit.seconds;
}

/// Lunes: torso, core y habilidades (~60 min), después de 10 min de
/// calentamiento.
const torsoTests = [
  TestItem('wall_handstand', 'Pino pecho a la pared', TestUnit.seconds),
  TestItem('pullup', 'Dominadas pronas estrictas', TestUnit.reps),
  TestItem('dips', 'Fondos en paralelas', TestUnit.reps),
  TestItem('one_arm_pushup', 'Flexión a una mano', TestUnit.reps, perSide: true),
  TestItem('pike_pushup', 'Pike push-up', TestUnit.reps),
  TestItem('hanging_leg_raise', 'Elevaciones colgado estrictas', TestUnit.reps),
  TestItem('hollow_hold', 'Hollow hold con la lumbar pegada', TestUnit.seconds),
  TestItem('tuck_up', 'Tuck-up', TestUnit.reps),
  TestItem('reverse_crunch', 'Encogimiento inverso con bajada de 3 s', TestUnit.reps),
  TestItem('tuck_lsit', 'L-sit recogido', TestUnit.seconds),
  TestItem('pushup', 'Flexiones normales', TestUnit.reps),
  TestItem('dead_hang', 'Colgarse de la barra', TestUnit.seconds),
];

/// Miércoles: piernas, después del FIFA 11+ y antes de la sesión.
const legTests = [
  TestItem('broad_jump', 'Salto largo desde parado', TestUnit.cm, hint: 'El mejor de 3 intentos.'),
  TestItem('bulgarian_split_squat', 'Búlgara sin peso', TestUnit.reps, perSide: true),
  TestItem('sl_calf_raise', 'Elevación de talón a una pierna', TestUnit.reps, perSide: true),
  TestItem('pistol_box', 'Pistol a la altura de la cama o silla', TestUnit.reps, perSide: true),
];

const allTests = [...torsoTests, ...legTests];

TestItem? testItem(String id) => allTests.where((t) => t.id == id).firstOrNull;

/// Descanso entre pruebas.
const testRestSec = 180;

enum TestPart { torso, piernas }

/// Qué parte del test toca `date` en el v3.1 que empezó el lunes `start`, y
/// cuál (1, 2 o 3). null si ese día no hay test.
({int round, TestPart part})? scheduledTest(DateTime start, DateTime date) {
  final s = dateOnly(start);
  final d = dateOnly(date);
  final testDay = v31TestDate(s);
  for (final (round, week) in const [(1, 1), (2, 6), (3, 9)]) {
    final monday = addDays(s, (week - 1) * 7);
    final wednesday = addDays(monday, 2);
    // El Test 3 de torso va con las pruebas del viernes (11 dic).
    final torsoDay = round == 3 ? testDay : monday;
    if (d == torsoDay) return (round: round, part: TestPart.torso);
    if (d == wednesday) return (round: round, part: TestPart.piernas);
  }
  return null;
}

/// Un resultado: el valor de una prueba (un lado, si es por lado).
class TestResult {
  const TestResult({required this.round, required this.item, required this.value, this.side, this.clean = true});

  final int round;
  final String item;
  final String? side;
  final double value;
  final bool clean;
}

/// Lo que cuenta de una prueba en un test: la suma no, el lado más débil
/// (marca el trabajo); sin lados, el valor.
double? testValue(List<TestResult> results, int round, String item) {
  final xs = results.where((r) => r.round == round && r.item == item).map((r) => r.value).toList();
  if (xs.isEmpty) return null;
  return xs.reduce((a, b) => a < b ? a : b);
}

/// % de mejora respecto del Test 1.
double? improvement(double? first, double? later) =>
    first == null || later == null || first == 0 ? null : (later - first) / first * 100;

/// Dosis inicial (§19.11): reps, el tope del rango al 70–75 % del máximo;
/// isométricos, series del 50–60 % del máximo. null en el salto.
String? initialDose(TestItem item, double max) {
  if (item.unit == TestUnit.cm || max <= 0) return null;
  if (item.isHold) {
    final lo = (max * .5).round();
    final hi = (max * .6).round();
    return 'Series de $lo–$hi s';
  }
  final lo = (max * .70).floor();
  final hi = (max * .75).round();
  if (hi < 1) return null;
  return lo == hi || lo < 1 ? 'Tope del rango: $hi reps' : 'Tope del rango: $lo–$hi reps';
}

String formatTestValue(TestItem item, double v) =>
    '${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(1)} ${item.unit.short}';
