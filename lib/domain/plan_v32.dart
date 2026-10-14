import 'dates.dart';

const v32Scheme = 'v3.2';

enum KneeTrainingMode { normal, noImpact, isometricsOnly, rest }

KneeTrainingMode kneeTrainingMode(int? kneeStairs, {bool restOnly = false}) =>
    restOnly
        ? KneeTrainingMode.rest
        : kneeStairs == null || kneeStairs <= 2
            ? KneeTrainingMode.normal
            : kneeStairs < 5
                ? KneeTrainingMode.noImpact
                : KneeTrainingMode.isometricsOnly;

bool kneeThreeDayAlert(DateTime today, Map<String, int?> values) => [
      for (var i = 0; i < 3; i++) values[dayKey(addDays(today, -i))]
    ].every((v) => v != null && v >= 3);

bool mobilityBenchmarkDue(DateTime start, DateTime date) {
  final elapsed = daysBetween(start, date);
  return elapsed >= 2 && (elapsed - 2) % 28 == 0;
}

String? benchmarkError(
    String item, double? value, bool? touches, String? side) {
  if (item == 'shoulder_wall') {
    return touches == null || value != null || side != null
        ? 'Indica sí o no'
        : null;
  }
  if (!['knee_to_wall', 'seated_pike', 'pancake', 'deep_squat']
      .contains(item)) {
    return 'Prueba desconocida';
  }
  if (value == null ||
      !value.isFinite ||
      (item != 'seated_pike' && value < 0)) {
    return 'Valor inválido';
  }
  if (item == 'knee_to_wall' ? !['I', 'D'].contains(side) : side != null) {
    return 'Lado inválido';
  }
  if (touches != null) return 'Unidad inválida';
  return null;
}

int maintenanceRounds(int week) =>
    ((week <= 5 ? week : week - 6) == 4) ? 10 : 6;

const v32ExerciseNames = <String, String>{
  'copenhagen': 'Copenhague',
  'seated_soleus': 'Sóleo sentado con mochila',
  'tibialis_wall': 'Tibial en la pared',
  'band_external_rotation': 'Rotación externa con banda',
  'prone_y_t': 'Y-T prono',
  'support_hold': 'Support hold en paralelas',
  'flying_sprint': 'Sprint lanzado',
  'scap_pullup': 'Scap pull-up',
  'scap_pushup': 'Flexiones escapulares',
  'wall_sit': 'Sentadilla isométrica en la pared',
  'side_lying_hip_abduction': 'Abducción de cadera de lado',
  'reverse_nordic': 'Nórdico inverso',
  'lateral_step_down': 'Bajada lateral del escalón',
  'landing_stick': 'Aterrizaje clavado',
  'intervals_15_15': intervals1515,
};

/// Intervalos del martes desde la semana 5 (§19.13); los agrega el día.
const intervals1515 = 'Intervalos 15/15';

/// Variantes físicas del aterrizaje clavado por semana (§19.16).
const landingBilateral = 'landing_bilateral';
const landingUnilateral = 'landing_unilateral';
const landingLateral = 'landing_lateral';

const v32Purposes = <String, String>{
  'Copenhague': 'Aductores y control de la ingle en cambios de dirección.',
  'Sóleo sentado con mochila': 'Sóleo para aceleración y sprint.',
  'Tibial en la pared': 'Dorsiflexión, espinillas y frenadas.',
  'Rotación externa con banda': 'Manguito rotador y control del hombro.',
  'Y-T prono': 'Trapecio inferior y control escapular.',
  'Support hold en paralelas': 'Control con brazos rectos para habilidades.',
  'Sprint lanzado': 'Practicar velocidad máxima de forma progresiva.',
  'Scap pull-up': 'Depresión escapular colgado.',
  'Flexiones escapulares': 'Protracción y serrato con brazos rectos.',
  'Sentadilla isométrica en la pared': 'Trabajo isométrico de cuádriceps.',
  'Abducción de cadera de lado': 'Glúteo medio y control de la rodilla.',
  'Nórdico inverso': 'Cuádriceps en posición alargada.',
  'Bajada lateral del escalón': 'Control de la rodilla sobre el pie.',
  'Aterrizaje clavado': 'Alinear y estabilizar el aterrizaje.',
  intervals1515: 'Capacidad de repetir esfuerzos cortos, como en el partido.',
};

const v32PurposeGoals = <String, String>{
  'Copenhague': 'Sin lesiones',
  'Sóleo sentado con mochila': 'Veloz',
  'Tibial en la pared': 'Ágil',
  'Rotación externa con banda': 'Sin lesiones',
  'Y-T prono': 'Sin lesiones',
  'Support hold en paralelas': 'Fuerte',
  'Sprint lanzado': 'Veloz',
  'Scap pull-up': 'Fuerte',
  'Flexiones escapulares': 'Fuerte',
  'Sentadilla isométrica en la pared': 'Sin lesiones',
  'Abducción de cadera de lado': 'Sin lesiones',
  'Nórdico inverso': 'Fuerte',
  'Bajada lateral del escalón': 'Ágil',
  'Aterrizaje clavado': 'Ágil',
  intervals1515: 'Veloz',
};
