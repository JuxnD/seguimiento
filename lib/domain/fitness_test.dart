import 'dates.dart';

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
  const TestItem(this.id, this.name, this.unit,
      {this.perSide = false, this.hint});

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
  TestItem('one_arm_pushup', 'Flexión a una mano', TestUnit.reps,
      perSide: true),
  TestItem('pike_pushup', 'Pike push-up', TestUnit.reps),
  TestItem('hanging_leg_raise', 'Elevaciones colgado estrictas', TestUnit.reps),
  TestItem('hollow_hold', 'Hollow hold con la lumbar pegada', TestUnit.seconds),
  TestItem('tuck_up', 'Tuck-up', TestUnit.reps),
  TestItem('reverse_crunch', 'Encogimiento inverso con bajada de 3 s',
      TestUnit.reps),
  TestItem('tuck_lsit', 'L-sit recogido', TestUnit.seconds),
  TestItem('pushup', 'Flexiones normales', TestUnit.reps),
  TestItem('dead_hang', 'Colgarse de la barra', TestUnit.seconds),
];

/// Miércoles: piernas, después del FIFA 11+ y antes de la sesión.
const legTests = [
  TestItem('broad_jump', 'Salto largo desde parado', TestUnit.cm,
      hint: 'El mejor de 3 intentos.'),
  TestItem('bulgarian_split_squat', 'Búlgara sin peso', TestUnit.reps,
      perSide: true),
  TestItem('sl_calf_raise', 'Elevación de talón a una pierna', TestUnit.reps,
      perSide: true),
  TestItem('pistol_box', 'Pistol a la altura de la cama o silla', TestUnit.reps,
      perSide: true),
];

const allTests = [...torsoTests, ...legTests];

TestItem? testItem(String id) => id == 'reverse_plank_forearm'
    ? const TestItem('reverse_plank_forearm',
        'Plancha inversa sobre antebrazos', TestUnit.seconds)
    : allTests.where((t) => t.id == id).firstOrNull;

/// Descanso entre pruebas.
const testRestSec = 180;

enum TestPart { torso, piernas }

enum TestStatus { pending, partial, complete }

List<TestItem> itemsFor(TestPart part) =>
    part == TestPart.torso ? torsoTests : legTests;

String? testResultError(TestItem item, double? value) {
  if (value == null || !value.isFinite) return 'Escribe un número finito';
  if (value < 0) return 'El valor no puede ser negativo';
  if (item.unit == TestUnit.reps && value != value.roundToDouble()) {
    return 'Las repeticiones deben ser enteras';
  }
  return null;
}

/// Qué parte del test toca `date` en el v3.1 que empezó el lunes `start`, y
/// cuál (1, 2 o 3). null si ese día no hay test.
({int round, TestPart part})? scheduledTest(DateTime start, DateTime date) {
  final s = dateOnly(start);
  final d = dateOnly(date);
  for (final (round, week) in const [(1, 1), (2, 6), (3, 9)]) {
    final monday = addDays(s, (week - 1) * 7);
    final wednesday = addDays(monday, 2);
    // §16.30.2: el Test 3 de torso también va el lunes (7 dic), así piernas
    // (mié 9) queda a 2 días del torso y el viernes 11 sólo lleva la Cindy.
    final torsoDay = monday;
    if (d == torsoDay) return (round: round, part: TestPart.torso);
    if (d == wednesday) return (round: round, part: TestPart.piernas);
  }
  return null;
}

/// Un resultado: el valor de una prueba (un lado, si es por lado).
class TestResult {
  const TestResult(
      {required this.round,
      required this.item,
      required this.value,
      this.side,
      this.clean = true,
      this.date,
      this.attemptId,
      this.protocolId = 'v31_12',
      this.conditions,
      this.baselineKey,
      this.limitedBy});

  /// Plan 052 (§16.27.3): qué la limitó (ver [testLimits]); null sin anotar.
  final String? limitedBy;

  /// Con piel, dolor o equipo el resultado no es un máximo real: se marca y
  /// se propone repetir la prueba.
  bool get notRealMax => testLimitsNotMax.contains(limitedBy);

  final int? attemptId;
  final String protocolId;
  final String? conditions;
  final String? baselineKey;

  final int round;
  final String item;
  final String? side;
  final double value;
  final bool clean;

  /// Día realmente guardado; null en evidencia sin procedencia temporal.
  final DateTime? date;
}

/// Qué limitó una prueba (§16.27.3), con su texto.
const testLimits = <String, String>{
  'tecnica': 'Técnica',
  'fuerza': 'Fuerza',
  'agarre': 'Agarre',
  'piel': 'Piel / callos',
  'dolor': 'Dolor',
  'equipo': 'Equipo',
};

/// Límites que hacen que el resultado no sea un máximo real.
const testLimitsNotMax = {'piel', 'dolor', 'equipo'};

/// Una prueba no hecha en un intento: queda pendiente con su motivo y el
/// material que falta (§16.27.3). No tiene valor.
class TestPendingItem {
  const TestPendingItem(
      {required this.item, required this.reason, this.requires = const []});

  final String item;
  final String reason;
  final List<String> requires;
}

/// SQLite contract is YYYY-MM-DD. tryParse alone normalizes e.g. February30;
/// a roundtrip prevents a legacy typo from becoming a different real date.
DateTime? recordedTestDate(String raw) {
  final parsed = DateTime.tryParse(raw);
  return parsed != null && dayKey(parsed) == raw ? parsed : null;
}

/// Lo que cuenta de una prueba en un test: la suma no, el lado más débil
/// (marca el trabajo); sin lados, el valor.
double? testValue(List<TestResult> results, int round, String item) {
  final definition = testItem(item);
  if (definition == null) return null;
  final rows = results
      .where((r) =>
          r.round == round &&
          r.item == item &&
          testResultError(definition, r.value) == null)
      .toList();
  if (testItem(item)?.perSide == true &&
      (!rows.any((r) => r.side == 'I') || !rows.any((r) => r.side == 'D'))) {
    return null;
  }
  if (rows.length != (definition.perSide ? 2 : 1)) return null;
  if (rows.any((r) =>
      definition.perSide ? r.side != 'I' && r.side != 'D' : r.side != null)) {
    return null;
  }
  final xs = rows.map((r) => r.value).toList();
  if (xs.isEmpty) return null;
  return xs.reduce((a, b) => a < b ? a : b);
}

/// Observado no significa apto: conservar las dudas visibles sin aumentar
/// dosis ni comparar un intento futuro o con fecha desconocida.
double? eligibleTestValue(List<TestResult> results, int round, String item,
    {DateTime? asOf, int? maxAgeDays}) {
  final value = testValue(results, round, item);
  if (value == null) return null;
  final rows =
      results.where((r) => r.round == round && r.item == item).toList();
  if (rows.any((r) =>
      !r.clean ||
      r.date == null ||
      (asOf != null &&
          (dateOnly(r.date!).isAfter(dateOnly(asOf)) ||
              (maxAgeDays != null &&
                  daysBetween(r.date!, asOf) > maxAgeDays))))) return null;
  // I/D guardados en fechas distintas no prueban un único intento bilateral.
  if (rows.map((r) => dayKey(r.date!)).toSet().length != 1) return null;
  return value;
}

int? latestEligibleTestRound(List<TestResult> results, String item,
    {DateTime? asOf, int? maxAgeDays}) {
  final rounds = results
      .where((r) => r.item == item)
      .map((r) => r.round)
      .toSet()
      .toList()
    ..sort();
  final eligible = rounds
      .where((round) =>
          eligibleTestValue(results, round, item,
              asOf: asOf, maxAgeDays: maxAgeDays) !=
          null)
      .toList();
  eligible.sort((a, b) {
    final da = results.firstWhere((r) => r.round == a && r.item == item).date!;
    final db = results.firstWhere((r) => r.round == b && r.item == item).date!;
    final cmp = da.compareTo(db);
    return cmp == 0 ? a.compareTo(b) : cmp;
  });
  return eligible.lastOrNull;
}

/// % de mejora respecto del Test 1.
double? improvement(double? first, double? later) =>
    first == null || later == null || first == 0
        ? null
        : (later - first) / first * 100;

/// Dosis inicial (§19.11): reps, el tope del rango al 70–75 % del máximo;
/// isométricos, series del 50–60 % del máximo. null en el salto.
String? initialDose(TestItem item, double max) {
  if (item.unit == TestUnit.cm || !max.isFinite || max <= 0) return null;
  if (item.isHold) {
    final lo = (max * .5).round();
    final hi = (max * .6).round();
    return 'Series de $lo–$hi s';
  }
  final lo = (max * .70).floor();
  final hi = (max * .75).round();
  if (hi < 1) return null;
  return lo == hi || lo < 1
      ? 'Tope del rango: $hi reps'
      : 'Tope del rango: $lo–$hi reps';
}

/// Plan 052 (§16.27.3): tope del rango del plan por prueba y la variante más
/// difícil que toca cuando la dosis lo supera: más reps no construyen fuerza.
const planRangeTops = <String, ({int top, String plan, String harder})>{
  'pullup': (
    top: 8,
    plan: 'Dominadas con mochila 4 × 5–8',
    harder: 'dominadas con mochila de 5 kg (sin mochila: bajada de 3 s)'
  ),
  'dips': (
    top: 10,
    plan: 'Fondos con mochila 4 × 6–10',
    harder: 'fondos con mochila de 5 kg (sin mochila: bajada de 3 s)'
  ),
  'pike_pushup': (
    top: 10,
    plan: 'Pike push-up 3 × 6–10',
    harder: 'pike con pies elevados (en una silla)'
  ),
  'hanging_leg_raise': (
    top: 12,
    plan: 'Elevaciones colgado 3 × 6–12',
    harder: 'toes-to-bar'
  ),
  'tuck_up': (
    top: 12,
    plan: 'Escalera del V-up, peldaño 1: 3 × 8–12',
    harder: 'el peldaño 2 del V-up (a una pierna)'
  ),
  'reverse_crunch': (
    top: 12,
    plan: 'Escalera del dragon flag, peldaño 1: 3 × 8–12',
    harder: 'el peldaño siguiente del dragon flag'
  ),
  'hollow_hold': (
    top: 30,
    plan: 'Hollow rock 3 × 20–30 s',
    harder: 'hollow con los brazos estirados atrás'
  ),
  'tuck_lsit': (
    top: 20,
    plan: 'L-sit 4 × 10–20 s',
    harder: 'L-sit con una pierna estirada'
  ),
  'reverse_plank_forearm': (
    top: 45,
    plan: 'Plancha inversa, peldaño 1: 3 × 20–45 s',
    harder: 'el peldaño siguiente de la plancha inversa'
  ),
};

/// Si la dosis del test supera el tope del rango del plan, qué variante más
/// difícil usar en vez de subir reps; null si la dosis cabe en el rango.
String? harderVariantAdvice(TestItem item, double max) {
  final range = planRangeTops[item.id];
  if (range == null || !max.isFinite || max <= 0) return null;
  final hi = item.isHold ? (max * .6).round() : (max * .75).round();
  if (hi <= range.top) return null;
  return 'Supera el tope del plan (${range.top}${item.isHold ? ' s' : ''}): no subas '
      '${item.isHold ? 'el tiempo' : 'las reps'}, pasa a ${range.harder} dentro de ${range.plan}.';
}

String formatTestValue(TestItem item, double v) => !v.isFinite || v < 0
    ? 'Inválido'
    : '${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(1)} ${item.unit.short}';
