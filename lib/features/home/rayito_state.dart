import '../../data/repositories/dashboard_repository.dart';
import '../../domain/enums.dart';
import '../../domain/mascot.dart';
import '../../domain/mascot_message.dart';
import '../../domain/readiness.dart';
import 'readiness_card.dart';

/// Lo que Rayito sabe del día (plan 052): la misma lectura para la tarjeta de
/// Hoy, el compañero flotante y el widget de inicio. Sale de la racha de Hoy y
/// del readiness de 032; no guarda nada.
class RayitoView {
  const RayitoView({
    required this.phase,
    required this.mood,
    required this.streak,
    required this.activeToday,
    required this.message,
    required this.todayLabel,
    required this.date,
    this.progressLine,
  });

  final MascotPhase phase;
  final MascotMood mood;
  final int streak;
  final bool activeToday;

  /// Frase de ánimo del día, sin culpa ni cifras inventadas.
  final String message;

  /// Lo que toca hoy, en palabras.
  final String todayLabel;

  /// Cuánto falta para el nivel siguiente; null en el último o si hoy toca
  /// descansar (no presiona).
  final String? progressLine;
  final DateTime date;

  String get days => streak == 1 ? '1 día' : '$streak días';
  String get streakLine => streak == 0 ? 'Sin racha todavía' : '$days de racha';
  String get levelLine => 'Nivel ${phase.level} de ${MascotPhase.levels}';
  String get semanticLabel => 'Rayito, $levelLine, $streakLine';
}

RayitoView rayitoView(TodayDashboard dashboard, ReadinessView? view) {
  final restAdvised = view != null &&
      !view.trainedAnyway &&
      view.advice.action != SuggestedAction.trainAsPlanned;
  final plannedRest =
      dashboard.planVersion != null && dashboard.dayType == DayType.descanso;
  final restOnly = view != null &&
      !view.trainedAnyway &&
      view.advice.action == SuggestedAction.restOnly;
  final todayLabel = dashboard.planVersion == null
      ? 'Configura tu rutina'
      : view == null
          ? 'Abre Hoy para revisar tu agenda'
          : restOnly
              ? 'Descanso'
              : restAdvised
                  ? 'Recuperación activa'
                  : dashboard.planB
                      ? 'Plan B: solo torso'
                      : dashboard.dayType.label;
  final streak = dashboard.streak;
  final phase = mascotPhase(streak);
  final toNext = daysToNextPhase(streak);
  return RayitoView(
    phase: phase,
    mood: mascotMood(
        streak: streak,
        activeToday: dashboard.activeToday,
        restAdvised: restAdvised || plannedRest),
    streak: streak,
    activeToday: dashboard.activeToday,
    message: mascotMessage(
        streak: streak,
        activeToday: dashboard.activeToday,
        restAdvised: restAdvised || plannedRest,
        restOnly: restOnly),
    todayLabel: todayLabel,
    date: dashboard.date,
    progressLine: toNext == null || restAdvised || plannedRest
        ? null
        : toNext == 1
            ? 'Un día más y sube al nivel ${phase.next!.level}.'
            : 'Faltan $toNext días para el nivel ${phase.next!.level}.',
  );
}

/// Consejos cortos para cuando lo tocas; uno distinto cada día.
const rayitoTips = [
  'Una rutina de 10 minutos también suma a la racha.',
  'Registrar tu sueño me ayuda a saber cómo vienes.',
  'Si algo molesta, anótalo: el plan se ajusta a ti.',
  'Proteína en cada comida: así se construye.',
  'Descansar bien también es progresar.',
  'Antes de entrenar, el check de la mañana dice cómo vienes.',
  'Pequeño y constante le gana a grande y de vez en cuando.',
];

String rayitoTipFor(DateTime day) =>
    rayitoTips[day.difference(DateTime(2026)).inDays.abs() % rayitoTips.length];
