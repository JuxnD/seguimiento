import 'package:flutter/material.dart';

import '../domain/enums.dart';
import 'theme.dart';

/// Icono y color por tipo de día. El mismo par se usa en Hoy, en el plan y en
/// la lista de sesiones, para que el tipo se reconozca sin leer.
class SessionStyle {
  const SessionStyle(this.icon, this.color);

  final IconData icon;
  final Color color;
}

const _circuito = Color(0xFFFF7A18); // naranja: el trabajo duro
const _ligero = AppColors.kcal; // naranja claro: la versión suave
const _progresion = Color(0xFFFF4D4D); // rojo: el día de récord
const _bloques = AppColors.protein; // azul: fuerza por bloques
const _futbol = AppColors.body; // verde: cardio de fin de semana
const _descanso = Color(0xFF9A9AA2); // gris: no hay nada que hacer
const _movilidad = Color(0xFFB39DDB); // lavanda: la noche, sin exigencia
const _superior = Color(0xFF5C9DFF); // azul claro: tirón y empuje (v3)
const _piernas = Color(0xFF7ED9A0); // verde menta: piernas y core (v3)
const _resistencia = Color(0xFFFF9F43); // ámbar: Cindy y Tabata (v3)
const _densidad = Color(0xFFFF6B6B); // rojo suave: densidad y burpees (v3)

SessionStyle styleForDay(DayType type) => switch (type) {
      DayType.circuito => const SessionStyle(Icons.replay_circle_filled, _circuito),
      DayType.circuitoLigero => const SessionStyle(Icons.change_circle_outlined, _ligero),
      DayType.progresion => const SessionStyle(Icons.trending_up, _progresion),
      DayType.bloques => const SessionStyle(Icons.view_week, _bloques),
      DayType.futbol => const SessionStyle(Icons.sports_soccer, _futbol),
      DayType.descanso => const SessionStyle(Icons.bedtime_outlined, _descanso),
      DayType.trenSuperior => const SessionStyle(Icons.fitness_center, _superior),
      DayType.piernas => const SessionStyle(Icons.directions_run, _piernas),
      DayType.resistencia => const SessionStyle(Icons.timer, _resistencia),
      DayType.densidad => const SessionStyle(Icons.local_fire_department, _densidad),
    };

SessionStyle styleForSession(SessionType type) => switch (type) {
      SessionType.circuito => styleForDay(DayType.circuito),
      SessionType.circuitoLigero => styleForDay(DayType.circuitoLigero),
      SessionType.progresion => styleForDay(DayType.progresion),
      SessionType.bloques => styleForDay(DayType.bloques),
      SessionType.otro => const SessionStyle(Icons.fitness_center, _descanso),
      SessionType.movilidad => const SessionStyle(Icons.self_improvement, _movilidad),
      SessionType.trenSuperior => styleForDay(DayType.trenSuperior),
      SessionType.piernas => styleForDay(DayType.piernas),
      SessionType.resistencia => styleForDay(DayType.resistencia),
      SessionType.densidad => styleForDay(DayType.densidad),
    };
