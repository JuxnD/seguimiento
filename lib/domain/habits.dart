/// Hábitos del Plan v3.1 (§19.3, §19.6): hidratación del partido, huevos
/// enteros del día, horas de sueño y la regla de decisión de cada 2 semanas.
/// Lógica pura.
library;

import 'dates.dart';
import 'progress.dart' show WeekAverage;
import 'search.dart';

// ---------------------------------------------------------------------------
// Hidratación del partido
// ---------------------------------------------------------------------------

/// Lo que dice el peso antes y después de jugar.
class SweatReading {
  const SweatReading({required this.lossKg, required this.ratePerHourL, required this.replaceL});

  /// Peso perdido en el partido (kg ≈ litros de sudor no repuestos).
  final double lossKg;

  /// Tasa de sudor: (peso perdido + lo bebido) por hora.
  final double ratePerHourL;

  /// Cuánto beber después: 1,5 L por cada kg perdido.
  final double replaceL;
}

/// null si falta algún peso o los minutos.
SweatReading? sweatReading({double? beforeKg, double? afterKg, int? fluidMl, required int? minutes}) {
  if (beforeKg == null || afterKg == null || minutes == null || minutes <= 0) return null;
  final loss = beforeKg - afterKg;
  final sweat = loss + (fluidMl ?? 0) / 1000;
  return SweatReading(
    lossKg: loss,
    ratePerHourL: sweat < 0 ? 0 : sweat / (minutes / 60),
    replaceL: loss > 0 ? loss * 1.5 : 0,
  );
}

// ---------------------------------------------------------------------------
// Huevos enteros
// ---------------------------------------------------------------------------

/// A partir de cuántos huevos enteros en el día avisa (§19.6). La meta es
/// 2–3 enteros más claras.
const eggWarnAt = 5;

/// Gramos de un huevo, para las entradas por peso.
const _eggGrams = 55.0;

/// Huevos enteros de una lista de ítems de comida (§16.15: el 5 oct un
/// desayuno de 4 huevos contaba 1). Por ítem, en este orden:
/// 1. si el alimento dice cuántos huevos trae por porción (`eggsPerUnit`),
///    porciones × huevos;
/// 2. si el nombre trae el número ("4 huevos", "huevos (3)", "huevos x2"),
///    ese número × porciones;
/// 3. si se llama "huevo" (sin claras): la cantidad en unidades, o los gramos
///    a 55 g el huevo; sin cantidad, uno.
double wholeEggs(Iterable<({String label, double? quantity, String? unit, double? eggsPerUnit})> items) {
  var total = 0.0;
  for (final i in items) {
    final unit = i.unit == null ? '' : foldText(i.unit!).trim();
    final byWeight = unit == 'g' || unit == 'ml';
    // Porciones: por peso no se sabe el tamaño de la porción; cuenta 1.
    final portions = i.quantity == null || byWeight ? 1.0 : i.quantity!;
    if (i.eggsPerUnit case final e? when e > 0) {
      total += e * portions;
      continue;
    }
    final name = foldText(i.label);
    if (!name.contains('huevo') || name.contains('clara')) continue;
    final n = _eggsInName(name);
    if (n != null) {
      total += n * portions;
    } else {
      total += i.quantity == null ? 1 : (unit == 'g' ? i.quantity! / _eggGrams : i.quantity!);
    }
  }
  return total;
}

/// "4 huevos", "huevos pericos (3)", "huevos x2", "2 huevos pericos" → el número.
int? _eggsInName(String folded) {
  final m = RegExp(r'(\d+)\s*huevos?|huevos?\s*x\s*(\d+)|huevos?[^\d(]*\((\d+)\)').firstMatch(folded);
  if (m == null) return null;
  return int.tryParse(m.group(1) ?? m.group(2) ?? m.group(3) ?? '');
}

// ---------------------------------------------------------------------------
// Sueño
// ---------------------------------------------------------------------------

/// Meta de horas en cama (§19.3).
const sleepGoalHours = 8.0;

/// Promedio y noches que llegaron a la meta.
({double average, int nightsAtGoal, int nights})? sleepSummary(Iterable<double> hours) {
  final list = hours.toList();
  if (list.isEmpty) return null;
  return (
    average: list.reduce((a, b) => a + b) / list.length,
    nightsAtGoal: list.where((h) => h >= sleepGoalHours).length,
    nights: list.length,
  );
}

// ---------------------------------------------------------------------------
// Regla de decisión de cada 2 semanas (§19.3)
// ---------------------------------------------------------------------------

enum KcalAction { subir, mantener, bajar, faltanDatos }

class DecisionReading {
  const DecisionReading(this.action, this.message, {this.kgPerWeek, this.lastWeek});

  final KcalAction action;
  final String message;

  /// Bajada semanal (positivo = baja; negativo = sube).
  final double? kgPerWeek;

  /// Lunes de la última semana completa usada.
  final DateTime? lastWeek;
}

/// Compara el promedio de la última semana completa con el de dos semanas
/// antes. Baja > 0,7 kg/sem → +150–200 kcal; 0,4–0,6 → no cambiar; < 0,25 y
/// la cintura (abdomen) sin moverse en 3 semanas → −150 kcal o +2.000 pasos.
/// Si caen las repeticiones, también se sube, pero eso lo decide quien
/// entrena: la regla lo recuerda.
DecisionReading twoWeekRule({
  required List<WeekAverage> weeks,
  required List<(DateTime, double)> abdomen,
  required DateTime today,
}) {
  final complete = weeks.where((w) => addDays(w.monday, 6).isBefore(dateOnly(today))).toList();
  if (complete.isEmpty) {
    return const DecisionReading(KcalAction.faltanDatos,
        'Hace falta una semana completa de pesajes en ayunas (mínimo martes, jueves y sábado).');
  }
  final last = complete.last;
  // Pesajes de hace un mes no dicen nada de hoy.
  if (daysBetween(last.monday, dateOnly(today)) > 14) {
    return DecisionReading(KcalAction.faltanDatos,
        'No hay pesajes recientes (el último promedio es de la semana del ${formatShort(last.monday)}). '
        'Pésate en ayunas martes, jueves y sábado.',
        lastWeek: last.monday);
  }
  final before = complete.where((w) => daysBetween(w.monday, last.monday) == 14).firstOrNull;
  if (before == null) {
    return DecisionReading(KcalAction.faltanDatos,
        'Se decide con dos semanas de distancia: la del ${formatShort(addDays(last.monday, -14))} no tiene pesajes.',
        lastWeek: last.monday);
  }
  final loss = (before.kg - last.kg) / 2;
  String rate() => loss >= 0 ? 'bajas ${_kg(loss)} kg/sem' : 'subes ${_kg(-loss)} kg/sem';
  if (loss > 0.7) {
    return DecisionReading(KcalAction.subir, '${_cap(rate())}: más rápido de lo que conviene. +150–200 kcal.',
        kgPerWeek: loss, lastWeek: last.monday);
  }
  if (loss >= 0.4) {
    return DecisionReading(KcalAction.mantener, '${_cap(rate())}: buen ritmo. No cambiar.',
        kgPerWeek: loss, lastWeek: last.monday);
  }
  if (loss >= 0.25) {
    return DecisionReading(KcalAction.mantener, '${_cap(rate())}: algo lento, pero aún dentro. No cambiar.',
        kgPerWeek: loss, lastWeek: last.monday);
  }
  final still = _waistStill(abdomen, today);
  if (still == true) {
    return DecisionReading(
        KcalAction.bajar, '${_cap(rate())} y la cintura no se mueve en 3 semanas: −150 kcal o +2.000 pasos.',
        kgPerWeek: loss, lastWeek: last.monday);
  }
  return DecisionReading(
    KcalAction.mantener,
    still == null
        ? '${_cap(rate())}. Falta el abdomen de hace 3 semanas para decidir; si no se mueve, −150 kcal o +2.000 pasos.'
        : '${_cap(rate())}, pero la cintura baja: no cambiar.',
    kgPerWeek: loss,
    lastWeek: last.monday,
  );
}

/// ¿El abdomen no se movió (menos de 0,5 cm) en las últimas 3 semanas? null
/// si no hay una toma de hace 3 semanas o más para comparar.
bool? _waistStill(List<(DateTime, double)> abdomen, DateTime today) {
  if (abdomen.isEmpty) return null;
  final sorted = [...abdomen]..sort((a, b) => a.$1.compareTo(b.$1));
  final latest = sorted.last;
  final old = sorted.where((m) => daysBetween(m.$1, latest.$1) >= 21).lastOrNull;
  if (old == null) return null;
  return old.$2 - latest.$2 < 0.5;
}

String _kg(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
String _cap(String s) => s[0].toUpperCase() + s.substring(1);
