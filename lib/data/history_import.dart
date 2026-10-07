import 'package:drift/drift.dart';

import '../domain/dates.dart';
import '../domain/enums.dart';
import 'corrections_29sep.dart' show CorrectionState, DataCorrection;
import 'database.dart';
import 'seed_plan.dart' show v31KcalFootball, v31KcalWeekday, v31ProteinMax, v31ProteinMin;

// Traspaso del 7 oct (§16.16, punto 0): el historial anterior a la app y las
// metas del v3.1 aplicadas ya, sin esperar a activar el plan. Se aplican desde
// Correcciones del traspaso, como las de §17.

/// Una entrada del historial del 26 ago al 21 sep
/// (`historial-importar-ago-sep-2026.json`). Desde el 7 sep es lo que
/// prescribía el plan de Google Calendar, no lo medido; el 11 y el 18 sep, 7
/// rondas confirmadas por el usuario. El fútbol de fin de semana está por
/// confirmar, sin minutos.
class HistoryEntry {
  const HistoryEntry(this.date, this.kind, {this.rounds, this.sets = const [], this.confirmed = false, this.note});

  final String date;

  /// 'detalle' (solo consta que entrenó), 'circuito', 'ligero', 'progresion',
  /// 'bloques' o 'futbol'.
  final String kind;
  final int? rounds;

  /// (ejercicio, series, reps, agarre): lo prescrito; un rango va con su mínimo.
  final List<(String, int, int, String?)> sets;
  final bool confirmed;
  final String? note;
}

const _round = [('Dominadas', 5), ('Flexiones', 10), ('Sentadillas', 15)];

const _blocksTue = [('Dominadas', 4, 6, 'prona'), ('Flexiones', 4, 14, null), ('Sentadillas', 3, 25, null)];
const _blocksThu = [('Dominadas', 3, 8, 'supina'), ('Flexiones', 5, 13, null), ('Sentadillas', 3, 20, null)];

/// Las 27 entradas, en orden.
const historyAugSep = [
  HistoryEntry('2026-08-26', 'detalle'),
  HistoryEntry('2026-08-27', 'detalle'),
  HistoryEntry('2026-08-28', 'detalle'),
  HistoryEntry('2026-08-29', 'futbol'),
  HistoryEntry('2026-08-30', 'futbol'),
  HistoryEntry('2026-08-31', 'detalle'),
  HistoryEntry('2026-09-01', 'detalle'),
  HistoryEntry('2026-09-02', 'detalle'),
  HistoryEntry('2026-09-03', 'detalle'),
  HistoryEntry('2026-09-04', 'detalle'),
  HistoryEntry('2026-09-05', 'futbol'),
  HistoryEntry('2026-09-06', 'futbol'),
  HistoryEntry('2026-09-07', 'circuito', rounds: 6),
  HistoryEntry('2026-09-08', 'bloques', sets: _blocksTue),
  HistoryEntry('2026-09-09', 'ligero', rounds: 5),
  HistoryEntry('2026-09-10', 'bloques', sets: _blocksThu),
  HistoryEntry('2026-09-11', 'progresion', rounds: 7, confirmed: true, note: '7 rondas limpias (dicho por el usuario)'),
  HistoryEntry('2026-09-12', 'futbol'),
  HistoryEntry('2026-09-13', 'futbol'),
  HistoryEntry('2026-09-14', 'circuito', rounds: 6),
  HistoryEntry('2026-09-15', 'bloques', sets: _blocksTue),
  HistoryEntry('2026-09-16', 'ligero', rounds: 5),
  HistoryEntry('2026-09-17', 'bloques', sets: _blocksThu),
  HistoryEntry('2026-09-18', 'progresion', rounds: 7, confirmed: true, note: '7 rondas limpias (dicho por el usuario)'),
  HistoryEntry('2026-09-19', 'futbol'),
  HistoryEntry('2026-09-20', 'futbol'),
  HistoryEntry('2026-09-21', 'circuito', rounds: 6),
];

/// Las entradas que faltan: un día que ya tiene algo registrado (importado o
/// no) no se vuelve a llenar.
Future<List<HistoryEntry>> _missing(AppDatabase db) async {
  final sessions = {for (final s in await db.select(db.sessions).get()) s.date};
  final games = {for (final g in await db.select(db.footballGames).get()) g.date};
  return [
    for (final e in historyAugSep)
      if (!(e.kind == 'futbol' ? games : sessions).contains(e.date)) e,
  ];
}

Future<void> _insert(AppDatabase db, HistoryEntry e) async {
  if (e.kind == 'futbol') {
    await db.into(db.footballGames).insert(FootballGamesCompanion.insert(
          date: e.date,
          minutes: 0,
          imported: const Value(true),
          notes: const Value('Fin de semana de fútbol por confirmar (historial importado)'),
        ));
    return;
  }
  final type = switch (e.kind) {
    'circuito' => SessionType.circuito,
    'ligero' => SessionType.circuitoLigero,
    'progresion' => SessionType.progresion,
    'bloques' => SessionType.bloques,
    _ => SessionType.otro,
  };
  final context = e.kind == 'detalle'
      ? 'Sesión de calistenia (detalle no registrado). Historial importado.'
      : e.confirmed
          ? 'Historial importado: ${e.note}'
          : 'Historial importado: lo que prescribía el plan (Google Calendar), no lo medido.';
  final id = await db.into(db.sessions).insert(SessionsCompanion.insert(
        date: e.date,
        type: type,
        roundsDone: Value(e.rounds),
        plannedRounds: Value(e.rounds),
        context: Value(context),
        imported: const Value(true),
      ));
  final perExercise = <int, int>{};
  Future<void> set(String name, int reps) async {
    final exId = await _exerciseId(db, name);
    final idx = perExercise[exId] = (perExercise[exId] ?? 0) + 1;
    await db.into(db.sessionSets).insert(
          SessionSetsCompanion.insert(sessionId: id, exerciseId: exId, setIndex: idx, reps: reps),
        );
  }

  for (var r = 0; r < (e.rounds ?? 0); r++) {
    for (final (name, reps) in _round) {
      await set(name, reps);
    }
  }
  for (final (name, sets, reps, _) in e.sets) {
    for (var i = 0; i < sets; i++) {
      await set(name, reps);
    }
  }
}

Future<int> _exerciseId(AppDatabase db, String name) async {
  final row = await (db.select(db.exercises)..where((t) => t.name.equals(name))).getSingleOrNull();
  return row?.id ?? db.into(db.exercises).insert(ExercisesCompanion.insert(name: name));
}

/// Correcciones del traspaso del 7 oct.
final corrections7Oct = <DataCorrection>[
  DataCorrection(
    id: 'metas-v31',
    date: 'mié 7 oct',
    title: 'Metas del v3.1 desde ya',
    change: '$v31KcalWeekday kcal entre semana, $v31KcalFootball en días de fútbol, '
        'proteína $v31ProteinMin–$v31ProteinMax g (§19.3)',
    check: (db) async {
      final p = await (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingle();
      final done = p.kcalTarget == v31KcalWeekday &&
          p.kcalTargetFootball == v31KcalFootball &&
          p.proteinMin == v31ProteinMin &&
          p.proteinMax == v31ProteinMax;
      return done ? CorrectionState.done : CorrectionState.pending;
    },
    apply: (db) => (db.update(db.profiles)..where((t) => t.id.equals(1))).write(const ProfilesCompanion(
          kcalTarget: Value(v31KcalWeekday),
          kcalTargetFootball: Value(v31KcalFootball),
          proteinMin: Value(v31ProteinMin),
          proteinMax: Value(v31ProteinMax),
        )),
  ),
  DataCorrection(
    id: 'historial-ago-sep',
    date: '26 ago – 21 sep',
    title: 'Historial antes de la app',
    change: '${historyAugSep.length} entradas marcadas como importadas: 19 sesiones y 8 fines de semana de fútbol '
        'por confirmar. Cuentan para totales y rachas, no para récords ni medias.',
    check: (db) async => (await _missing(db)).isEmpty ? CorrectionState.done : CorrectionState.pending,
    apply: (db) async {
      for (final e in await _missing(db)) {
        await _insert(db, e);
      }
    },
  ),
];

/// Primer día con algo registrado (incluido lo importado). null si nada.
Future<DateTime?> firstDataDay(AppDatabase db) async {
  Future<String?> minOf(TableInfo<Table, Object?> t, GeneratedColumn<String> c) async {
    final m = c.min();
    return (db.selectOnly(t)..addColumns([m])).map((r) => r.read(m)).getSingle();
  }

  final candidates = [
    await minOf(db.sessions, db.sessions.date),
    await minOf(db.footballGames, db.footballGames.date),
    await minOf(db.meals, db.meals.date),
    await minOf(db.bodyWeights, db.bodyWeights.date),
    await minOf(db.dailySteps, db.dailySteps.date),
  ].whereType<String>().toList()
    ..sort();
  return candidates.isEmpty ? null : parseDay(candidates.first);
}
