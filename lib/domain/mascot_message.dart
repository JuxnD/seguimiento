/// Lo que dice Rayito hoy (plan 049): una frase corta de ánimo hecha con datos
/// reales del día. Nunca culpa ni inventa cifras; el lema de la marca es
/// «Construye tu mejor versión».
library;

import 'mascot.dart';

/// `streak` cuenta hasta hoy si ya hubo registro y hasta ayer si no (hoy
/// todavía no corta la racha).
String mascotMessage({
  required int streak,
  required bool activeToday,
  required bool restAdvised,
  bool restOnly = false,
}) {
  final phase = mascotPhase(streak);
  if (activeToday) {
    if (streak == phase.fromDays && phase != MascotPhase.dormido) {
      return '¡Rayito pasó a ${phase.label}! $streak ${_days(streak)} construyendo tu mejor versión.';
    }
    return 'Hoy ya sumaste. $streak ${_days(streak)} seguidos construyendo tu mejor versión.';
  }
  if (restOnly) return 'Hoy toca descansar. Rayito te acompaña a tu ritmo.';
  if (restAdvised) {
    return 'Descansar también es parte del plan. Si te apetece moverte suave, esa actividad cuenta.';
  }
  if (streak == 0) {
    return 'Una actividad guardada despierta a Rayito. Empieza a tu ritmo.';
  }
  final tomorrow = mascotPhase(streak + 1);
  if (tomorrow != phase) {
    return 'Guarda una actividad hoy y Rayito pasa a ${tomorrow.label}.';
  }
  return 'Guarda una actividad hoy y llegas a ${streak + 1} días.';
}

String _days(int n) => n == 1 ? 'día' : 'días';
