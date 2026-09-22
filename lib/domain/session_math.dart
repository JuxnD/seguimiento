import 'dart:math' as math;

/// Circuito neto = total − calentamiento − enfriamiento (nunca negativo).
int circuitNetSec({required int totalSec, required int warmupSec, required int cooldownSec}) =>
    math.max(0, totalSec - warmupSec - cooldownSec);

/// Estimación de rondas cuando se pierde la cuenta:
/// neto ÷ (tiempo medio por ronda + descanso entre rondas).
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
