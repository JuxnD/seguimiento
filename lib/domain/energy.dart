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
      SessionType.movilidad => cooldownMet,
    };

const warmupMet = 3.5;
const cooldownMet = 2.3;
const restMet = 2.0;

/// Fútbol recreativo ("soccer, casual, general", 15610): 7,0.
const footballMet = 7.0;

/// kcal de un partido. null sin peso.
double? footballKcal({required int minutes, required double? weightKg}) {
  if (weightKg == null || weightKg <= 0 || minutes <= 0) return null;
  return footballMet * weightKg * minutes / 60;
}

/// Zancada al caminar estimada por la estatura (≈ 41,5 % de la talla); sin
/// estatura, 0,75 m, la de un adulto promedio.
double strideMeters(double? heightCm) => heightCm == null || heightCm <= 0 ? 0.75 : heightCm * 0.415 / 100;

/// Kilómetros caminados según los pasos y la zancada.
double stepsKm(int steps, {double? heightCm}) => steps * strideMeters(heightCm) / 1000;

/// kcal de caminar **por encima del reposo**: la ecuación de marcha del ACSM
/// da 0,1 mL O₂·kg⁻¹·m⁻¹ en llano, ≈ 0,5 kcal por kg y por km. No incluye
/// lo que el cuerpo gasta igual sin moverse. null sin peso.
double? stepsKcal(int steps, {required double? weightKg, double? heightCm}) {
  if (weightKg == null || weightKg <= 0 || steps <= 0) return null;
  return 0.5 * weightKg * stepsKm(steps, heightCm: heightCm);
}

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
