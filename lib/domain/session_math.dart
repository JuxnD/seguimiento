import 'dart:math' as math;

/// Tiempo de circuito = total − calentamiento − enfriamiento: todo lo que va
/// del inicio del trabajo al final, descansos incluidos. Las vueltas del
/// contador se miden sobre este tiempo (cada vuelta incluye su descanso).
int circuitSpanSec({required int totalSec, required int warmupSec, required int cooldownSec}) =>
    math.max(0, totalSec - warmupSec - cooldownSec);

/// Trabajo neto = tiempo de circuito − descansos (nunca negativo). Es el
/// tiempo realmente trabajando. Sesiones viejas o manuales sin descanso
/// registrado (`restSec` 0) conservan el neto de antes.
int circuitNetSec({required int totalSec, required int warmupSec, required int cooldownSec, int restSec = 0}) =>
    math.max(0, circuitSpanSec(totalSec: totalSec, warmupSec: warmupSec, cooldownSec: cooldownSec) - restSec);

/// Estimación de rondas cuando se pierde la cuenta:
/// tiempo de circuito ÷ (tiempo medio por ronda + descanso entre rondas).
/// Recibe el tiempo de circuito **con** descansos (`circuitSpanSec`), que es
/// sobre lo que se miden las vueltas.
///
/// Si el tiempo medio sale de las vueltas del contador, ya incluye el
/// descanso: usar `restSec: 0` para no contarlo dos veces.
int estimateRounds({required int netSec, required int meanRoundSec, int restSec = 30}) {
  final perRound = meanRoundSec + restSec;
  if (perRound <= 0 || netSec <= 0) return 0;
  return netSec ~/ perRound;
}

/// Convierte marcas acumuladas del contador (segundos desde el inicio del
/// circuito al completar cada ronda) en duración de cada ronda.
List<int> lapDurations(List<int> cumulativeSec) {
  final out = <int>[];
  var prev = 0;
  for (final t in cumulativeSec) {
    out.add(t - prev);
    prev = t;
  }
  return out;
}

/// Trabajo de cada ronda a partir de las marcas acumuladas y del descanso
/// medido después de cada una: la vuelta k va de la marca k−1 a la k y lleva
/// dentro el descanso que siguió a la ronda k−1, que aquí se descuenta.
/// null si los descansos no se midieron (listas de distinto largo).
List<int>? roundWork(List<int> cumulativeSec, List<int> restAfterSec) {
  if (cumulativeSec.isEmpty || restAfterSec.length != cumulativeSec.length) return null;
  final laps = lapDurations(cumulativeSec);
  return [
    for (var i = 0; i < laps.length; i++) math.max(0, laps[i] - (i == 0 ? 0 : restAfterSec[i - 1])),
  ];
}

/// Diferencia de trabajo entre la última ronda y la primera (positivo = la
/// última fue más lenta). Indicador de degradación; null con menos de 2.
int? firstToLastDelta(List<int> workSec) => workSec.length < 2 ? null : workSec.last - workSec.first;

int? meanSec(List<int> values) =>
    values.isEmpty ? null : (values.reduce((a, b) => a + b) / values.length).round();
