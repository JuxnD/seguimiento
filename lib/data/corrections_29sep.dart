import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'database.dart';

// Correcciones de datos del traspaso del 29 sep 2026 (§17). Cada una busca el
// registro **exacto** que describe el traspaso y solo lo toca si sigue como
// estaba: si el usuario ya lo corrigió a mano, o el registro no existe, no se
// hace nada. Se aplican desde Ajustes, después de verlas y confirmarlas.

/// En qué está una corrección.
enum CorrectionState {
  /// El registro está como lo describe el traspaso: se puede corregir.
  pending,

  /// Ya tiene el valor correcto (o lo que había que borrar ya no está).
  done,

  /// No se encontró el registro que describe el traspaso: no se toca nada.
  missing,
}

class DataCorrection {
  const DataCorrection({
    required this.id,
    required this.date,
    required this.title,
    required this.change,
    required this.check,
    required this.apply,
  });

  final String id;

  /// "mié 23 sep".
  final String date;
  final String title;

  /// "RPE 10 → 4".
  final String change;
  final Future<CorrectionState> Function(AppDatabase db) check;
  final Future<void> Function(AppDatabase db) apply;
}

/// Las correcciones del 29 sep, en el orden del traspaso.
final corrections29Sep = <DataCorrection>[
  _sessionRpe('rpe-23', '2026-09-23', 'mié 23 sep', SessionType.circuitoLigero, from: 10, to: 4),
  _sessionRpe('rpe-24', '2026-09-24', 'jue 24 sep', SessionType.bloques, from: null, to: 6),
  _sessionRpe('rpe-25', '2026-09-25', 'vie 25 sep', SessionType.progresion, from: null, to: 7),
  DataCorrection(
    id: 'notas-25',
    date: 'vie 25 sep',
    title: 'Progresión · notas',
    change: 'vacías → "$_notes25"',
    check: (db) async {
      final s = await _session(db, '2026-09-25', SessionType.progresion);
      if (s == null) return CorrectionState.missing;
      if (s.notes == _notes25) return CorrectionState.done;
      return (s.notes ?? '').trim().isEmpty ? CorrectionState.pending : CorrectionState.missing;
    },
    apply: (db) async {
      final s = (await _session(db, '2026-09-25', SessionType.progresion))!;
      await (db.update(db.sessions)..where((t) => t.id.equals(s.id))).write(const SessionsCompanion(notes: Value(_notes25)));
    },
  ),
  DataCorrection(
    id: 'plancha-28',
    date: 'lun 28 sep',
    title: 'Plancha lateral',
    change: '0 s → 40 s por lado (cerca del fallo)',
    check: (db) async {
      final sets = await _plankSets(db);
      if (sets.isEmpty) return CorrectionState.missing;
      if (sets.every((s) => s.reps == 40)) return CorrectionState.done;
      return sets.any((s) => s.reps == 0) ? CorrectionState.pending : CorrectionState.missing;
    },
    apply: (db) async {
      for (final s in await _plankSets(db)) {
        if (s.reps != 0) continue;
        await (db.update(db.sessionSets)..where((t) => t.id.equals(s.id))).write(const SessionSetsCompanion(reps: Value(40)));
      }
    },
  ),
  DataCorrection(
    id: 'desayuno-28',
    date: 'lun 28 sep',
    title: 'Desayuno · salchichón',
    change: '200 g → 110 g (1.140 → 960 kcal)',
    check: (db) async {
      final item = await _salchichon28(db);
      if (item == null) return CorrectionState.missing;
      if (item.quantity == 110) return CorrectionState.done;
      return item.quantity == 200 ? CorrectionState.pending : CorrectionState.missing;
    },
    apply: (db) async {
      final item = (await _salchichon28(db))!;
      const f = 110 / 200;
      await (db.update(db.mealItems)..where((t) => t.id.equals(item.id))).write(MealItemsCompanion(
        quantity: const Value(110),
        kcal: Value(item.kcal * f),
        protein: Value(item.protein * f),
        carbs: Value(item.carbs * f),
        fat: Value(item.fat * f),
      ));
    },
  ),
  _retype('merienda-25', '2026-09-25', 'vie 25 sep', '16:47', MealSlot.merienda, MealSlot.desayuno,
      'huevos + pan + leche'),
  DataCorrection(
    id: 'cena-27',
    date: 'dom 27 sep',
    title: 'Cena 19:48 con dos comidas',
    change: 'se separa: Almuerzo 650 kcal (mondongo + arroz) y Cena 1.100 kcal (pasta)',
    check: (db) async {
      final found = await _split27(db);
      if (found != null) return CorrectionState.pending;
      final lunch = await _meals(db, '2026-09-27', MealSlot.almuerzo);
      return lunch.isNotEmpty ? CorrectionState.done : CorrectionState.missing;
    },
    apply: (db) async {
      final (dinner, lunchItem, dinnerItem) = (await _split27(db))!;
      final lunchId = await db.into(db.meals).insert(MealsCompanion.insert(
            date: dinner.date,
            slot: MealSlot.almuerzo,
          ));
      await (db.update(db.mealItems)..where((t) => t.id.equals(lunchItem.id))).write(MealItemsCompanion(
        mealId: Value(lunchId),
        // Un renglón que se llama como la comida no dice qué fue.
        label: lunchItem.label.trim().toLowerCase() == 'almuerzo'
            ? const Value('Sopa de mondongo + arroz')
            : const Value.absent(),
      ));
      if (dinnerItem != null && dinnerItem.label.trim().toLowerCase() == 'cena') {
        await (db.update(db.mealItems)..where((t) => t.id.equals(dinnerItem.id)))
            .write(const MealItemsCompanion(label: Value('Pasta con queso y salchicha (plato grande)')));
      }
    },
  ),
  _retype('merienda-28', '2026-09-28', 'lun 28 sep', '16:10', MealSlot.merienda, MealSlot.almuerzo, 'pasta'),
  DataCorrection(
    id: 'cerrar-24-28',
    date: '24–28 sep',
    title: 'Estado de los días',
    change: 'abiertos → cerrados (entran a los promedios)',
    check: (db) async {
      final days = await _loggedCloseDays(db);
      if (days.isEmpty) return CorrectionState.missing;
      final closed = {for (final c in await db.select(db.closedDays).get()) c.date};
      return days.every(closed.contains) ? CorrectionState.done : CorrectionState.pending;
    },
    apply: (db) async {
      for (final d in await _loggedCloseDays(db)) {
        await db.into(db.closedDays).insertOnConflictUpdate(ClosedDaysCompanion.insert(date: d));
      }
    },
  ),
  DataCorrection(
    id: 'sesion-2oct',
    date: 'vie 2 oct',
    title: 'Progresión de 9 rondas que no se guardó',
    change: 'se crea: 9/9 rondas, total 22:12, neto ≈ 7:42, 45 dominadas · 90 flexiones · 135 sentadillas; '
        'queda sin revisar para anotar el RPE',
    check: (db) async {
      final rows = await (db.select(db.sessions)..where((t) => t.date.equals('2026-10-02'))).get();
      return rows.any((s) => s.type.isTraining) ? CorrectionState.done : CorrectionState.pending;
    },
    apply: _recover2Oct,
  ),
  DataCorrection(
    id: 'duplicado-29',
    date: 'mar 29 sep',
    title: 'Desayuno 15:51 (1.140 kcal)',
    change: 'se borra: duplicado accidental del "Repetir" (§16.7)',
    check: (db) async => await _duplicate29(db) == null ? CorrectionState.done : CorrectionState.pending,
    apply: (db) async {
      final meal = (await _duplicate29(db))!;
      await (db.delete(db.meals)..where((t) => t.id.equals(meal.id))).go();
    },
  ),
];

/// La sesión récord del viernes 2 oct (§16.9): terminó en el cronómetro y se
/// perdió al salir del resumen. Se crea con los tiempos del traspaso, ya con
/// el descanso corregido (3:30 registrado → ≈ 4:00: R3 se comió 30 s), y
/// queda "sin revisar" para que el usuario anote RPE y criterios.
Future<void> _recover2Oct(AppDatabase db) async {
  final id = await db.into(db.sessions).insert(SessionsCompanion.insert(
        date: '2026-10-02',
        type: SessionType.progresion,
        totalSec: const Value(22 * 60 + 12),
        warmupSec: const Value(7 * 60 + 30),
        cooldownSec: const Value(3 * 60),
        restSec: const Value(4 * 60),
        roundsDone: const Value(9),
        plannedRounds: const Value(9),
        pendingReview: const Value(true),
        context: const Value('Recuperada del traspaso del 3 oct: no se guardó al salir del resumen. '
            'Descanso registrado 3:30, corregido a ≈ 4:00 (el de R2 quedó en 0:00).'),
      ));
  final ids = <String, int>{};
  for (final name in ['Dominadas', 'Flexiones', 'Sentadillas']) {
    final row = await (db.select(db.exercises)..where((t) => t.name.equals(name))).getSingleOrNull();
    ids[name] = row?.id ?? await db.into(db.exercises).insert(ExercisesCompanion.insert(name: name));
  }
  const reps = {'Dominadas': 5, 'Flexiones': 10, 'Sentadillas': 15};
  for (var round = 1; round <= 9; round++) {
    for (final e in reps.entries) {
      await db.into(db.sessionSets).insert(SessionSetsCompanion.insert(
            sessionId: id,
            exerciseId: ids[e.key]!,
            setIndex: round,
            reps: e.value,
          ));
    }
  }
}

const _notes25 = 'Flexiones y dominadas fáciles hasta R8, técnica constante';
const _closeDays = ['2026-09-24', '2026-09-25', '2026-09-26', '2026-09-27', '2026-09-28'];

DataCorrection _sessionRpe(String id, String day, String label, SessionType type, {required int? from, required int to}) =>
    DataCorrection(
      id: id,
      date: label,
      title: '${type.label} · RPE',
      change: '${from ?? '—'} → $to',
      check: (db) async {
        final s = await _session(db, day, type);
        if (s == null) return CorrectionState.missing;
        if (s.rpe == to) return CorrectionState.done;
        return s.rpe == from ? CorrectionState.pending : CorrectionState.missing;
      },
      apply: (db) async {
        final s = (await _session(db, day, type))!;
        await (db.update(db.sessions)..where((t) => t.id.equals(s.id))).write(SessionsCompanion(rpe: Value(to)));
      },
    );

DataCorrection _retype(
        String id, String day, String label, String time, MealSlot from, MealSlot to, String what) =>
    DataCorrection(
      id: id,
      date: label,
      title: '${from.label} $time ($what)',
      change: '${from.label} → ${to.label}',
      check: (db) async {
        if ((await _mealAt(db, day, from, time)) != null) return CorrectionState.pending;
        return (await _mealAt(db, day, to, time)) != null ? CorrectionState.done : CorrectionState.missing;
      },
      apply: (db) async {
        final meal = (await _mealAt(db, day, from, time))!;
        await (db.update(db.meals)..where((t) => t.id.equals(meal.id))).write(MealsCompanion(slot: Value(to)));
      },
    );

/// De los días 24 a 28, los que tienen comidas: cerrar un día vacío no dice nada.
Future<List<String>> _loggedCloseDays(AppDatabase db) async {
  final rows = await (db.select(db.meals)..where((t) => t.date.isIn(_closeDays))).get();
  final logged = {for (final m in rows) m.date};
  return [for (final d in _closeDays) if (logged.contains(d)) d];
}

/// La sesión de ese tipo en ese día, solo si es una.
Future<SessionRow?> _session(AppDatabase db, String day, SessionType type) async {
  final rows =
      await (db.select(db.sessions)..where((t) => t.date.equals(day) & t.type.equalsValue(type))).get();
  return rows.length == 1 ? rows.single : null;
}

Future<List<MealRow>> _meals(AppDatabase db, String day, MealSlot slot) =>
    (db.select(db.meals)..where((t) => t.date.equals(day) & t.slot.equalsValue(slot))).get();

Future<MealRow?> _mealAt(AppDatabase db, String day, MealSlot slot, String time) async {
  final rows = (await _meals(db, day, slot)).where((m) => m.time == time).toList();
  return rows.length == 1 ? rows.single : null;
}

Future<List<MealItemRow>> _items(AppDatabase db, int mealId) =>
    (db.select(db.mealItems)..where((t) => t.mealId.equals(mealId))).get();

double _kcal(List<MealItemRow> items) => items.fold(0.0, (a, i) => a + i.kcal);

/// Series de plancha lateral del lunes 28.
Future<List<SessionSetRow>> _plankSets(AppDatabase db) async {
  final plank = await (db.select(db.exercises)..where((t) => t.name.equals('Plancha lateral'))).getSingleOrNull();
  if (plank == null) return const [];
  final sessions = await (db.select(db.sessions)..where((t) => t.date.equals('2026-09-28'))).get();
  if (sessions.isEmpty) return const [];
  return (db.select(db.sessionSets)
        ..where((t) => t.sessionId.isIn(sessions.map((s) => s.id)) & t.exerciseId.equals(plank.id)))
      .get();
}

/// El salchichón del desayuno del lunes 28 (un solo desayuno ese día).
Future<MealItemRow?> _salchichon28(AppDatabase db) async {
  final breakfasts = await _meals(db, '2026-09-28', MealSlot.desayuno);
  if (breakfasts.length != 1) return null;
  final items = (await _items(db, breakfasts.single.id))
      .where((i) => i.label.toLowerCase().contains('salchich'))
      .toList();
  return items.length == 1 ? items.single : null;
}

/// La cena de las 19:48 del domingo 27 con el almuerzo dentro: (cena,
/// renglón del almuerzo, renglón de la cena).
Future<(MealRow, MealItemRow, MealItemRow?)?> _split27(AppDatabase db) async {
  final dinner = await _mealAt(db, '2026-09-27', MealSlot.cena, '19:48');
  if (dinner == null) return null;
  final items = await _items(db, dinner.id);
  if (items.length < 2) return null;
  bool isLunch(MealItemRow i) {
    final l = i.label.trim().toLowerCase();
    return l == 'almuerzo' || l.contains('mondongo') || (i.kcal - 650).abs() < 1;
  }

  final lunch = items.where(isLunch).toList();
  if (lunch.length != 1) return null;
  final rest = items.where((i) => i.id != lunch.single.id).toList();
  return (dinner, lunch.single, rest.length == 1 ? rest.single : null);
}

/// El desayuno de las 15:51 del martes 29 con 1.140 kcal.
Future<MealRow?> _duplicate29(AppDatabase db) async {
  final meal = await _mealAt(db, '2026-09-29', MealSlot.desayuno, '15:51');
  if (meal == null) return null;
  return (_kcal(await _items(db, meal.id)) - 1140).abs() < 1 ? meal : null;
}

/// Estado de cada corrección.
Future<Map<String, CorrectionState>> checkCorrections(AppDatabase db, [List<DataCorrection>? list]) async => {
      for (final c in list ?? corrections29Sep) c.id: await c.check(db),
    };

/// Aplica las pendientes en una sola transacción. Devuelve cuántas aplicó.
Future<int> applyPendingCorrections(AppDatabase db, [List<DataCorrection>? list]) => db.transaction(() async {
      var n = 0;
      for (final c in list ?? corrections29Sep) {
        if (await c.check(db) != CorrectionState.pending) continue;
        await c.apply(db);
        n++;
      }
      return n;
    });
