/// Plan 052 (§16.27.5): suplementos. Lo puro: si es creatina, cuántas tomas
/// quedan en el envase, la constancia del rango y las 4 semanas en que la
/// creatina sube el peso con agua intramuscular.
library;

import 'dates.dart';
import 'search.dart' show foldText;

/// Días desde el inicio en que la creatina sube el peso por agua (4 semanas).
const creatineWindowDays = 28;

/// Con estas tomas o menos (y más de 0), Hoy avisa.
const lowStockServings = 7;

/// La nota del peso durante esas 4 semanas (gráfica, Cuerpo e informe).
const creatineWaterNote =
    'Creatina: +0,5–1,5 kg de agua intramuscular esperada';

/// "Creatina", "creatina monohidratada", "Creatine": sin mayúsculas ni tildes.
bool isCreatineName(String name) => foldText(name).contains('creatin');

/// Del inicio al día 28, ambos incluidos.
({DateTime start, DateTime end}) creatineWindow(DateTime start) => (
      start: dateOnly(start),
      end: addDays(dateOnly(start), creatineWindowDays - 1),
    );

/// ¿El día cae en las 4 semanas desde el inicio?
bool inCreatineWindow(DateTime start, DateTime day) {
  final w = creatineWindow(start);
  final d = dateOnly(day);
  return !d.isBefore(w.start) && !d.isAfter(w.end);
}

/// ¿Las 4 semanas desde el inicio tocan el rango [from, to]?
bool creatineWindowOverlaps(DateTime start, DateTime from, DateTime to) {
  final w = creatineWindow(start);
  return !w.end.isBefore(dateOnly(from)) && !w.start.isAfter(dateOnly(to));
}

/// Tomas que quedan: las del envase menos las marcadas desde el inicio.
/// null si falta el envase o todavía no empieza. Nunca menos de 0.
int? remainingServings({
  required int? servingsPerPack,
  required DateTime? start,
  required Iterable<String> logDates,
}) {
  if (servingsPerPack == null || start == null) return null;
  final from = dayKey(start);
  final taken = logDates.where((d) => d.compareTo(from) >= 0).length;
  final left = servingsPerPack - taken;
  return left < 0 ? 0 : left;
}

/// El aviso de Hoy: null si sobran tomas (más de [lowStockServings]) o no
/// se sabe cuántas quedan.
String? stockMessage(String name, int? remaining) {
  if (remaining == null || remaining > lowStockServings) return null;
  if (remaining <= 0) {
    return 'Se acabaron las tomas de $name. Si abriste otro envase, '
        'súmale sus tomas en Ajustes → Suplementos.';
  }
  return remaining == 1
      ? 'Te queda 1 toma de $name'
      : 'Te quedan $remaining tomas de $name';
}

/// Constancia: días con toma de los días desde el inicio dentro de
/// [from, to], sin contar los que aún no llegan. null si no hay días.
({int taken, int days})? supplementConstancy({
  required DateTime? start,
  required Iterable<String> logDates,
  required DateTime from,
  required DateTime to,
  required DateTime today,
}) {
  if (start == null) return null;
  final first = dateOnly(start).isAfter(dateOnly(from)) ? dateOnly(start) : dateOnly(from);
  final last = dateOnly(today).isBefore(dateOnly(to)) ? dateOnly(today) : dateOnly(to);
  if (last.isBefore(first)) return null;
  final a = dayKey(first), b = dayKey(last);
  final taken = logDates.toSet().where((d) => d.compareTo(a) >= 0 && d.compareTo(b) <= 0).length;
  return (taken: taken, days: daysBetween(first, last) + 1);
}

/// Un suplemento para el informe: datos planos, sin la base.
class SupplementEntry {
  const SupplementEntry({
    required this.name,
    this.start,
    this.active = true,
    this.logs = const {},
  });

  final String name;

  /// null: todavía no empieza.
  final DateTime? start;
  final bool active;

  /// Días con toma (`YYYY-MM-DD`).
  final Set<String> logs;

  bool get isCreatine => isCreatineName(name);
}
