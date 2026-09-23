/// Qué franja corresponde a una hora del día. Sirve para proponer la franja al
/// registrar y para avisar cuando no cuadra (un desayuno a las 14:57).
library;

import 'enums.dart';

/// Ventanas por franja, en minutos desde medianoche: [inicio, fin).
/// La cena cruza la medianoche hasta las 5 a. m.
const slotWindows = <MealSlot, (int, int)>{
  MealSlot.desayuno: (5 * 60, 11 * 60),
  MealSlot.almuerzo: (11 * 60, 15 * 60 + 30),
  MealSlot.merienda: (15 * 60 + 30, 19 * 60),
  MealSlot.cena: (19 * 60, 29 * 60), // 19:00 → 05:00 del día siguiente
};

int _minutes(int hour, int minute) => hour * 60 + minute;

bool _inWindow(MealSlot slot, int minutes) {
  final window = slotWindows[slot];
  if (window == null) return true;
  final (start, end) = window;
  // Las horas de madrugada se leen como continuación de la noche.
  final m = minutes < 5 * 60 ? minutes + 24 * 60 : minutes;
  return m >= start && m < end;
}

/// Franja que corresponde a una hora.
MealSlot slotForTime(int hour, int minute) {
  final m = _minutes(hour, minute);
  for (final slot in slotWindows.keys) {
    if (_inWindow(slot, m)) return slot;
  }
  return MealSlot.cena;
}

/// Si la hora no cuadra con la franja elegida, devuelve la franja que sí
/// cuadra. null = todo bien (o la comida es "otro", que admite cualquier hora).
///
/// `toleranceMin` evita avisar por un almuerzo a las 11:05 registrado como
/// desayuno tardío: el margen se aplica a ambos bordes de la ventana.
MealSlot? slotMismatch(MealSlot slot, String? time, {int toleranceMin = 30}) {
  if (slot == MealSlot.otro || time == null) return null;
  final parts = time.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;

  final m = _minutes(hour, minute);
  final window = slotWindows[slot]!;
  final (start, end) = window;
  final normalized = m < 5 * 60 ? m + 24 * 60 : m;
  if (normalized >= start - toleranceMin && normalized < end + toleranceMin) return null;
  return slotForTime(hour, minute);
}
