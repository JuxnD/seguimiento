/// Hábitos del Plan v3.1 (§19.3, §19.6): hidratación del partido, huevos
/// enteros del día, horas de sueño y la regla de decisión de cada 2 semanas.
/// Lógica pura.
library;

import 'dates.dart';
import 'progress.dart' show WeekAverage;
import 'search.dart';
import 'supplements.dart' show creatineWindow, creatineWindowOverlaps;

// ---------------------------------------------------------------------------
// Hidratación del partido
// ---------------------------------------------------------------------------

/// Lo que dice el peso antes y después de jugar.
class SweatReading {
  const SweatReading({required this.lossKg, required this.ratePerHourL, required this.replaceL, this.replaceMinL = 0});

  /// Peso perdido en el partido (kg ≈ litros de sudor no repuestos).
  final double lossKg;

  /// Tasa de sudor: (peso perdido + lo bebido) por hora.
  final double ratePerHourL;

  /// Cuánto beber después: 1,5 L por cada kg perdido (tope del rango).
  final double replaceL;

  /// Piso del rango (§16.26.5): 1,25 L por kg perdido.
  final double replaceMinL;

  /// «1,3–1,5 L con sal», o null si no hay que reponer.
  String? get replaceText => replaceL <= 0 ? null : '${_l(replaceMinL)}–${_l(replaceL)} L con algo de sal';
  static String _l(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
}

/// null si falta algún peso, los minutos o lo bebido, o si no se confirmó que
/// los dos pesajes son comparables (plan 040). Lo bebido desconocido no es 0:
/// un 0 anotado sí vale. `weightsComparable`: true sólo con confirmación
/// explícita; false (después de comer, medición alterada) y null (sin
/// confirmar o de antes) no dan lectura.
SweatReading? sweatReading({
  double? beforeKg,
  double? afterKg,
  int? fluidMl,
  required int? minutes,
  bool? weightsComparable,
}) {
  if (beforeKg == null || afterKg == null || fluidMl == null || minutes == null || minutes <= 0) return null;
  if (weightsComparable != true) return null;
  if (!beforeKg.isFinite || !afterKg.isFinite || beforeKg <= 0 || afterKg <= 0 || fluidMl < 0) return null;
  final loss = beforeKg - afterKg;
  final sweat = loss + fluidMl / 1000;
  return SweatReading(
    lossKg: loss,
    ratePerHourL: sweat < 0 ? 0 : sweat / (minutes / 60),
    replaceL: loss > 0 ? loss * 1.5 : 0,
    replaceMinL: loss > 0 ? loss * 1.25 : 0,
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
  const DecisionReading(this.action, this.message, {this.kgPerWeek, this.lastWeek, this.creatine = false});

  final KcalAction action;
  final String message;

  /// Bajada semanal (positivo = baja; negativo = sube).
  final double? kgPerWeek;

  /// Lunes de la última semana completa usada.
  final DateTime? lastWeek;

  /// La última semana cae en las 4 semanas de la creatina (§16.27.5): el
  /// peso que no baja no se lee como grasa; decide la cintura.
  final bool creatine;
}

/// Compara el promedio de la última semana completa con el de dos semanas
/// antes. Baja > 0,7 kg/sem → +150–200 kcal; 0,4–0,6 → no cambiar; < 0,25 y
/// la cintura (abdomen) sin moverse en 3 semanas → −150 kcal o +2.000 pasos.
/// Si caen las repeticiones, también se sube, pero eso lo decide quien
/// entrena: la regla lo recuerda.
///
/// Creatina (§16.27.5): si la última semana toca sus 4 semanas desde
/// [creatineStart], el peso sube 0,5–1,5 kg de agua intramuscular. Ahí un
/// peso que no baja (o sube) no se lee como grasa: decide sólo la cintura.
/// Una bajada de 0,25 kg/sem o más se lee igual que siempre: el agua sólo
/// puede esconder bajada, no inventarla.
DecisionReading twoWeekRule({
  required List<WeekAverage> weeks,
  required List<(DateTime, double)> abdomen,
  required DateTime today,
  DateTime? creatineStart,
}) {
  final complete = weeks.where((w) => addDays(w.monday, 6).isBefore(dateOnly(today)) && w.count >= 3).toList()
    ..sort((a, b) => a.monday.compareTo(b.monday));
  if (complete.isEmpty) {
    return const DecisionReading(KcalAction.faltanDatos,
        'Hace falta una semana completa de pesajes en ayunas (mínimo martes, jueves y sábado).');
  }
  final last = complete.last;
  // Pesajes de hace un mes no dicen nada de hoy.
  if (daysBetween(last.monday, dateOnly(today)) > 14) {
    return DecisionReading(
        KcalAction.faltanDatos,
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
  if (creatineStart != null && creatineWindowOverlaps(creatineStart, last.monday, addDays(last.monday, 6))) {
    final w = creatineWindow(creatineStart);
    final why = '${_cap(rate())}, pero es la creatina (del ${formatShort(w.start)} al ${formatShort(w.end)}): '
        '+0,5–1,5 kg de agua intramuscular esperada, no grasa. Decide la cintura';
    return DecisionReading(
      still == true ? KcalAction.bajar : KcalAction.mantener,
      switch (still) {
        true => '$why: no se mueve en 3 semanas, −150 kcal o +2.000 pasos.',
        false => '$why: baja, no cambiar.',
        null => '$why: falta una medida reciente de abdomen y otra comparable de hace 3 semanas; '
            'no cambiar hasta registrarla.',
      },
      kgPerWeek: loss,
      lastWeek: last.monday,
      creatine: true,
    );
  }
  if (still == true) {
    return DecisionReading(
        KcalAction.bajar, '${_cap(rate())} y la cintura no se mueve en 3 semanas: −150 kcal o +2.000 pasos.',
        kgPerWeek: loss, lastWeek: last.monday);
  }
  return DecisionReading(
    KcalAction.mantener,
    still == null
        ? '${_cap(rate())}. Falta una medida reciente de abdomen y otra comparable de hace 3 semanas; registra antes de ajustar metas.'
        : '${_cap(rate())}, pero la cintura baja: no cambiar.',
    kgPerWeek: loss,
    lastWeek: last.monday,
  );
}

/// ¿El abdomen no se movió (menos de 0,5 cm) en las últimas 3 semanas? null
/// si no hay una toma de hace 3 semanas o más para comparar.
bool? _waistStill(List<(DateTime, double)> abdomen, DateTime today) {
  if (abdomen.isEmpty) return null;
  final sorted = abdomen.where((m) => !dateOnly(m.$1).isAfter(dateOnly(today))).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  if (sorted.isEmpty) return null;
  final latest = sorted.last;
  if (daysBetween(latest.$1, today) > 14) return null;
  final old = sorted.where((m) => daysBetween(m.$1, latest.$1) >= 21 && daysBetween(m.$1, latest.$1) <= 35).lastOrNull;
  if (old == null) return null;
  return old.$2 - latest.$2 < 0.5;
}

String _kg(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
String _cap(String s) => s[0].toUpperCase() + s.substring(1);
