import 'dates.dart';

/// Plan 053: «rodar la programación un día». Un corrimiento es la fecha real
/// desde la que el owner rodó: ese día queda libre y las sesiones siguientes
/// de esa semana van un día más tarde. El fútbol queda fijo (es un partido
/// real); el primer descanso absorbe el corrimiento y, si no hay descanso
/// antes del domingo, la última sesión de la semana se pierde. La semana
/// siguiente vuelve a lo normal. Los corrimientos se aplican en el orden en
/// que se pidieron, así que rodar dos veces corre dos días.
enum ShiftDayKind {
  /// Fútbol: no se mueve y la cadena de sesiones lo salta.
  fixed,

  /// Descanso: absorbe el corrimiento.
  rest,

  /// Sesión: se corre.
  session,
}

/// Domingo de la semana de `d`: ningún corrimiento cruza a la siguiente.
DateTime shiftWeekEnd(DateTime d) => addDays(weekAnchor(d), 6);

/// Qué fecha nominal del plan se ve el día real `real`, o null si ese día
/// quedó libre porque su sesión se corrió al siguiente. `shifts` en el orden
/// en que se pidieron; `kindOf` clasifica una fecha nominal.
DateTime? shiftedNominal(DateTime real, List<DateTime> shifts,
    ShiftDayKind Function(DateTime nominal) kindOf) {
  final day = dateOnly(real);
  final week = weekAnchor(day);
  // Sólo cuentan los corrimientos de la misma semana.
  final relevant = [
    for (final s in shifts)
      if (weekAnchor(dateOnly(s)) == week) dateOnly(s)
  ];
  final memo = <(int, DateTime), DateTime?>{};

  DateTime? content(DateTime x, int applied) {
    if (applied == 0) return x;
    final key = (applied, x);
    if (memo.containsKey(key)) return memo[key];
    DateTime? prev(DateTime y) => content(y, applied - 1);
    ShiftDayKind kindAt(DateTime y) {
      final c = prev(y);
      return c == null ? ShiftDayKind.rest : kindOf(c);
    }

    final start = relevant[applied - 1];
    DateTime? result;
    if (x.isBefore(start) ||
        kindAt(x) == ShiftDayKind.fixed ||
        kindAt(start) != ShiftDayKind.session) {
      // Antes del corrimiento, un partido, o se rodó un día sin sesión.
      result = prev(x);
    } else {
      final movable = <DateTime>[];
      final end = shiftWeekEnd(start);
      for (var y = start; !y.isAfter(end); y = addDays(y, 1)) {
        final kind = kindAt(y);
        if (kind == ShiftDayKind.fixed) continue;
        movable.add(y);
        if (y != start && kind == ShiftDayKind.rest) break;
      }
      final i = movable.indexOf(x);
      result = i < 0
          ? prev(x)
          : i == 0
              ? null
              : prev(movable[i - 1]);
    }
    memo[key] = result;
    return result;
  }

  return content(day, relevant.length);
}

/// Fecha real en la que se ve el contenido de la fecha nominal `nominal`.
/// Si el corrimiento lo dejó fuera de la semana, se queda en su día: un test
/// nunca desaparece por rodar.
DateTime shiftedReal(DateTime nominal, List<DateTime> shifts,
        ShiftDayKind Function(DateTime nominal) kindOf) =>
    shiftedRealOrNull(nominal, shifts, kindOf) ?? dateOnly(nominal);

/// Como [shiftedReal], pero null si el contenido quedó sin día esta semana.
DateTime? shiftedRealOrNull(DateTime nominal, List<DateTime> shifts,
    ShiftDayKind Function(DateTime nominal) kindOf) {
  final n = dateOnly(nominal);
  final week = weekAnchor(n);
  for (var i = 0; i < 7; i++) {
    final x = addDays(week, i);
    if (shiftedNominal(x, shifts, kindOf) == n) return x;
  }
  return null;
}

/// Si `real` quedó libre por un corrimiento: el contenido nominal que tenía
/// justo antes de rodar (lo que «pasa a mañana»). null si no quedó libre.
DateTime? vacatedContent(DateTime real, List<DateTime> shifts,
    ShiftDayKind Function(DateTime nominal) kindOf) {
  if (shiftedNominal(real, shifts, kindOf) != null) return null;
  for (var k = 1; k <= shifts.length; k++) {
    if (shiftedNominal(real, shifts.sublist(0, k), kindOf) == null) {
      return shiftedNominal(real, shifts.sublist(0, k - 1), kindOf);
    }
  }
  return null;
}

/// Contenidos nominales de la semana que el corrimiento deja sin día (la
/// última sesión cuando no hay descanso que lo absorba).
List<DateTime> shiftDropped(DateTime anyDay, List<DateTime> shifts,
    ShiftDayKind Function(DateTime nominal) kindOf) {
  final week = weekAnchor(dateOnly(anyDay));
  final shown = <DateTime>{
    for (var i = 0; i < 7; i++)
      if (shiftedNominal(addDays(week, i), shifts, kindOf) case final n?) n
  };
  return [
    for (var i = 0; i < 7; i++)
      if (!shown.contains(addDays(week, i)) &&
          kindOf(addDays(week, i)) == ShiftDayKind.session)
        addDays(week, i)
  ];
}
