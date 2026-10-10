import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/coach_repository.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/recovery.dart';

import '../support/sqlite_host.dart';

/// Plan 009, paso 5: 1.000 días de historia. La racha real no se trunca, el
/// resultado es idéntico a la lectura previa (copiada abajo tal como estaba
/// en la 1.22, sólo como referencia de equivalencia) y se cuentan consultas.
/// Los tiempos se imprimen como recibo; no se exige una aceleración.

/// La implementación de `loadReading` de la candidata 1.22 (`d2d3070`).
LoadReading referenceLoadReading(List<LoadItem> items, DateTime today) {
  final d0 = dateOnly(today);
  final todayItems = items.where((i) => dateOnly(i.date) == d0).toList();
  bool intenseOn(DateTime d) => items.any((i) => dateOnly(i.date) == d && i.intense);
  var streak = 0;
  var day = intenseOn(d0) ? d0 : addDays(d0, -1);
  final moderateToday = todayItems.any((i) => i.minutes > 0 && i.effort != null && i.effort! < 7);
  if (!intenseOn(d0) && moderateToday && todayItems.every((i) => i.effort != null)) day = d0;
  final end = day;
  while (intenseOn(day)) {
    streak++;
    day = addDays(day, -1);
  }
  return LoadReading(
    todayLoad: todayItems.fold(0, (a, i) => a + i.load),
    todayCount: todayItems.length,
    intenseStreak: streak,
    streakThrough: streak == 0 ? null : end,
  );
}

class _Count extends QueryInterceptor {
  int selects = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(QueryExecutor executor, String statement, List<Object?> args) {
    selects++;
    return super.runSelect(executor, statement, args);
  }
}

void main() {
  setUpAll(useHostSqlite);
  final today = DateTime(2026, 10, 20);

  /// 1.000 días: los últimos 800 intensos seguidos (peor caso de recorrido),
  /// fútbol suave los domingos (dos registros ese día).
  List<LoadItem> fixture([int days = 1000]) => [
        for (var i = 0; i < days; i++) ...[
          LoadItem(date: addDays(today, -i), minutes: 45, effort: i < 800 ? 8 : (i.isEven ? 5 : null)),
          if (addDays(today, -i).weekday == DateTime.sunday)
            LoadItem(date: addDays(today, -i), minutes: 90, effort: 6, isFootball: true),
        ],
      ];

  test('dominio: idéntico a la lectura previa en 1.000 días y en bordes', () {
    final items = fixture();
    LoadReading timed(String label, LoadReading Function() f) {
      final sw = Stopwatch()..start();
      final r = f();
      sw.stop();
      // ignore: avoid_print
      print('$label: ${sw.elapsedMicroseconds} µs por lectura (${items.length} registros, '
          '${Platform.operatingSystem} ${Platform.numberOfProcessors} núcleos)');
      return r;
    }

    final before = timed('previa', () => referenceLoadReading(items, today));
    final after = timed('actual', () => loadReading(items, today));
    expect(before.intenseStreak, 800, reason: 'la racha real no se trunca a 7');
    expect((after.todayLoad, after.todayCount, after.intenseStreak, after.streakThrough),
        (before.todayLoad, before.todayCount, before.intenseStreak, before.streakThrough));

    // Bordes: hoy vacío, hoy moderado conocido, hoy sin esfuerzo, hoy intenso.
    for (final todayItems in [
      <LoadItem>[],
      [LoadItem(date: today, minutes: 30, effort: 5)],
      [LoadItem(date: today, minutes: 30)],
      [LoadItem(date: today, minutes: 30, effort: 9)],
    ]) {
      final base = [...fixture(200).where((i) => dateOnly(i.date) != today), ...todayItems];
      final a = referenceLoadReading(base, today);
      final b = loadReading(base, today);
      expect((b.todayLoad, b.todayCount, b.intenseStreak, b.streakThrough),
          (a.todayLoad, a.todayCount, a.intenseStreak, a.streakThrough));
    }
  });

  test('repositorio: 1.000 días en SQLite, dos consultas y la misma lectura', () async {
    final counter = _Count();
    final db = AppDatabase(NativeDatabase.memory().interceptWith(counter));
    await db.batch((b) {
      for (var i = 0; i < 1000; i++) {
        b.insert(
            db.sessions,
            SessionsCompanion.insert(
              date: dayKey(addDays(today, -i)),
              type: SessionType.bloques,
              totalSec: const Value(45 * 60),
              rpe: Value(i < 800 ? 8 : 5),
            ));
      }
    });
    final repo = CoachRepository(db);
    counter.selects = 0;
    final sw = Stopwatch()..start();
    final r = await repo.load(today);
    sw.stop();
    // ignore: avoid_print
    print('repositorio: ${counter.selects} consultas, ${sw.elapsedMilliseconds} ms (1.000 sesiones)');
    expect(counter.selects, 2, reason: 'sesiones y partidos, sin una consulta por día');
    expect(r.intenseStreak, 800);
    await db.close();
  });
}
