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

SessionStyle styleForDay(DayType type) => switch (type) {
      DayType.circuito => const SessionStyle(Icons.replay_circle_filled, _circuito),
      DayType.circuitoLigero => const SessionStyle(Icons.change_circle_outlined, _ligero),
      DayType.progresion => const SessionStyle(Icons.trending_up, _progresion),
      DayType.bloques => const SessionStyle(Icons.view_week, _bloques),
      DayType.futbol => const SessionStyle(Icons.sports_soccer, _futbol),
      DayType.descanso => const SessionStyle(Icons.bedtime_outlined, _descanso),
    };

SessionStyle styleForSession(SessionType type) => switch (type) {
      SessionType.circuito => styleForDay(DayType.circuito),
      SessionType.circuitoLigero => styleForDay(DayType.circuitoLigero),
      SessionType.progresion => styleForDay(DayType.progresion),
      SessionType.bloques => styleForDay(DayType.bloques),
      SessionType.otro => const SessionStyle(Icons.fitness_center, _descanso),
    };
