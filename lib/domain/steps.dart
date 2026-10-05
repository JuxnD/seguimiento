/// Pasos: la palanca de gasto más barata que falta. Un día de oficina típico
/// registró ~1.935; la meta es 7.500 entre semana. El fin de semana es fútbol
/// y no tiene meta.
library;

import 'dates.dart';

/// Meta de pasos de un día, o null si ese día no tiene (sábado y domingo).
int? stepsGoalFor(DateTime day, int weekdayTarget) => day.weekday <= DateTime.friday ? weekdayTarget : null;

/// Resumen de pasos de un rango. Solo cuenta los días registrados: un día sin
/// cifra no es un día de 0 pasos.
class StepsSummary {
  const StepsSummary({
    required this.days,
    required this.average,
    required this.weekdayDays,
    this.weekdayAverage,
    required this.weekdaysAtGoal,
  });

  final int days;
  final int average;
  final int weekdayDays;
  final int? weekdayAverage;
  final int weekdaysAtGoal;
}

StepsSummary? summarizeSteps(Map<DateTime, int> byDay, int weekdayTarget) {
  if (byDay.isEmpty) return null;
  final weekdays = {
    for (final e in byDay.entries)
      if (stepsGoalFor(dateOnly(e.key), weekdayTarget) != null) e.key: e.value,
  };
  int avg(Iterable<int> v) => (v.reduce((a, b) => a + b) / v.length).round();
  return StepsSummary(
    days: byDay.length,
    average: avg(byDay.values),
    weekdayDays: weekdays.length,
    weekdayAverage: weekdays.isEmpty ? null : avg(weekdays.values),
    weekdaysAtGoal: weekdays.values.where((s) => s >= weekdayTarget).length,
  );
}

/// Qué cifra queda en un día al traer los pasos de Health Connect, o null si
/// no hay que tocar nada:
/// - un día vacío toma lo sincronizado;
/// - un día que ya venía de Health Connect se actualiza (el reloj sigue
///   sumando durante el día);
/// - un día anotado a mano solo cambia si lo sincronizado es mayor: si el
///   usuario escribió más, es que contó pasos que el reloj no vio.
int? mergeSyncedSteps({required int? current, required String? currentSource, required int synced}) {
  if (synced <= 0) return null;
  if (current == null) return synced;
  if (currentSource == 'health_connect') return synced == current ? null : synced;
  return synced > current ? synced : null;
}

/// Quién escribió el último registro de pasos en Health Connect y cuándo
/// termina. La app del reloj (INNOVA S-WATCH, `com.moyoung.innov`) escribe por
/// lotes al sincronizar, con la hora de la sincronización: una caminata de
/// 2.028 pasos llegó como un solo registro de 3:05 a 3:06 p. m. (§16.14).
class StepsOrigin {
  const StepsOrigin({required this.at, required this.package, required this.label});

  final DateTime at;
  final String package;

  /// Nombre visible de la app; el paquete si Android no lo dejó ver.
  final String label;

  Map<String, Object?> toJson() => {'at': at.toIso8601String(), 'package': package, 'label': label};

  static StepsOrigin? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'], pkg = json['package'], label = json['label'];
    if (at is! String || pkg is! String) return null;
    final when = DateTime.tryParse(at);
    if (when == null) return null;
    return StepsOrigin(at: when, package: pkg, label: label is String ? label : pkg);
  }
}

/// Paquetes conocidos, por si Android no deja leer el nombre visible.
const _knownStepsApps = {'com.moyoung.innov': 'INNOVA S-WATCH'};

/// Nombre para mostrar: el visible si Android lo dio; si no, uno conocido; si
/// no, el paquete tal cual.
String stepsAppName(StepsOrigin o) {
  final label = o.label.trim();
  if (label.isNotEmpty && label != o.package) return label;
  return _knownStepsApps[o.package] ?? o.package;
}

/// Sin registros del reloj en tanto tiempo, lo más probable es que su app no
/// haya sincronizado: los pasos están en el reloj, no en el teléfono.
const watchSyncStaleAfter = Duration(hours: 6);

/// true si hay que pedir abrir la app del reloj: sin registro conocido o con
/// el último más viejo que [watchSyncStaleAfter].
bool watchSyncStale(DateTime? lastRecord, DateTime now) =>
    lastRecord == null || now.difference(lastRecord) > watchSyncStaleAfter;

/// "INNOVA S-WATCH · 3:06 p. m."; "· ayer 3:06 p. m."; "· jue 2 oct 3:06 p. m.".
String stepsOriginLine(StepsOrigin o, DateTime now) {
  final days = daysBetween(o.at, now);
  final day = switch (days) {
    0 => '',
    1 => 'ayer ',
    _ => '${weekdayShort(o.at.weekday)} ${formatShort(o.at)} ',
  };
  return '${stepsAppName(o)} · $day${formatTime12(o.at)}';
}
