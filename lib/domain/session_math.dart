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

int? meanSec(List<int> values) =>
    values.isEmpty ? null : (values.reduce((a, b) => a + b) / values.length).round();
