/// Gasto aproximado de una sesión con equivalentes metabólicos (MET):
/// kcal ≈ MET × peso (kg) × horas. Es una **estimación**, no una medición:
/// no conoce la frecuencia cardíaca ni la técnica, y puede errar ±30 %. Sirve
/// para ver cómo crece el gasto mientras avanza la sesión y para comparar
/// sesiones entre sí, no para cuadrar la dieta al gramo.
///
/// Valores tomados del Compendio de Actividades Físicas (Ainsworth et al.,
/// 2011 y su actualización 2024):
/// - Circuito vigoroso con poco descanso ("circuit training… minimal rest,
///   vigorous", 02040) y calistenia vigorosa (02022): 8,0.
/// - Calistenia moderada (02020) y entrenamiento de fuerza por series: 3,8–5.
/// - Calentamiento (movilidad, trote suave): 3,5.
/// - Estiramiento suave (02101): 2,3.
/// - Descanso de pie entre series, recuperando: 2,0.
library;

import 'enums.dart';

/// MET del trabajo según el tipo de sesión.
double workMet(SessionType type) => switch (type) {
      SessionType.circuito || SessionType.progresion => 8.0,
      SessionType.circuitoLigero => 5.0,
      SessionType.bloques || SessionType.otro => 5.0,
    };

const warmupMet = 3.5;
const cooldownMet = 2.3;
const restMet = 2.0;

/// kcal de una sesión según el tiempo en cada fase. null sin peso: sin él
/// cualquier número sería inventado.
double? sessionKcal({
  required SessionType type,
  required double? weightKg,
  int warmupSec = 0,
  int workSec = 0,
  int restSec = 0,
  int cooldownSec = 0,
}) {
  if (weightKg == null || weightKg <= 0) return null;
  double part(double met, int sec) => met * weightKg * (sec < 0 ? 0 : sec) / 3600;
  return part(warmupMet, warmupSec) +
      part(workMet(type), workSec) +
      part(restMet, restSec) +
      part(cooldownMet, cooldownSec);
}
