import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/supplements.dart';
import '../database.dart';

/// Un suplemento con lo que queda en el envase (plan 052, §16.27.5).
class SupplementStock {
  const SupplementStock({required this.supplement, required this.remaining});

  final SupplementRow supplement;

  /// null: sin envase anotado o todavía sin fecha de inicio.
  final int? remaining;

  /// El aviso de Hoy; null si no hace falta.
  String? get message => stockMessage(supplement.name, remaining);
}

/// Suplementos (§16.27.5): se dan de alta en Ajustes y la toma se marca en
/// el registro de la mañana. No sostienen la racha.
class SupplementRepository {
  SupplementRepository(this.db);

  final AppDatabase db;

  Future<List<SupplementRow>> all() =>
      (db.select(db.supplements)..orderBy([(t) => OrderingTerm(expression: t.id)])).get();

  Stream<List<SupplementRow>> watchAll() =>
      (db.select(db.supplements)..orderBy([(t) => OrderingTerm(expression: t.id)])).watch();

  /// Alta. El nombre y la dosis van sin espacios de sobra.
  Future<int> add({
    required String name,
    required String dose,
    int? servingsPerPack,
    DateTime? start,
    bool active = true,
  }) {
    _check(name, servingsPerPack);
    return db.into(db.supplements).insert(SupplementsCompanion.insert(
          name: name.trim(),
          dose: dose.trim(),
          servingsPerPack: Value(servingsPerPack),
          startDate: Value(start == null ? null : dayKey(start)),
          active: Value(active),
        ));
  }

  /// Edición completa: lo que llega reemplaza lo guardado (inicio vacío =
  /// todavía no empieza).
  Future<void> edit(
    int id, {
    required String name,
    required String dose,
    int? servingsPerPack,
    DateTime? start,
    required bool active,
  }) async {
    _check(name, servingsPerPack);
    await (db.update(db.supplements)..where((t) => t.id.equals(id))).write(SupplementsCompanion(
      name: Value(name.trim()),
      dose: Value(dose.trim()),
      servingsPerPack: Value(servingsPerPack),
      startDate: Value(start == null ? null : dayKey(start)),
      active: Value(active),
    ));
  }

  Future<void> setActive(int id, bool active) =>
      (db.update(db.supplements)..where((t) => t.id.equals(id))).write(SupplementsCompanion(active: Value(active)));

  void _check(String name, int? servings) {
    if (name.trim().isEmpty) throw ArgumentError('Escribe el nombre del suplemento');
    if (servings != null && servings <= 0) throw ArgumentError('Las tomas del envase van de 1 en adelante');
  }

  /// Los que se toman ese día: activos y con inicio el mismo día o antes.
  Future<List<SupplementRow>> dueOn(DateTime day) async {
    final key = dayKey(day);
    return [
      for (final s in await all())
        if (s.active && s.startDate != null && s.startDate!.compareTo(key) <= 0) s
    ];
  }

  /// Ids con la toma marcada ese día.
  Future<Set<int>> logsOn(DateTime day) async {
    final rows = await (db.select(db.supplementLogs)..where((t) => t.date.equals(dayKey(day)))).get();
    return {for (final r in rows) r.supplementId};
  }

  /// Marca o quita la toma del día. Repetirlo no duplica ni falla.
  Future<void> setTaken(int supplementId, DateTime day, bool taken) async {
    final key = dayKey(day);
    if (taken) {
      await db
          .into(db.supplementLogs)
          .insert(SupplementLogsCompanion.insert(supplementId: supplementId, date: key), mode: InsertMode.insertOrIgnore);
    } else {
      await (db.delete(db.supplementLogs)..where((t) => t.supplementId.equals(supplementId) & t.date.equals(key))).go();
    }
  }

  /// Cambia la toma del día y devuelve si quedó marcada.
  Future<bool> toggle(int supplementId, DateTime day) => db.transaction(() async {
        final taken = (await logsOn(day)).contains(supplementId);
        await setTaken(supplementId, day, !taken);
        return !taken;
      });

  Future<List<String>> _logDates(int supplementId) async {
    final rows = await (db.select(db.supplementLogs)..where((t) => t.supplementId.equals(supplementId))).get();
    return [for (final r in rows) r.date];
  }

  /// Tomas que quedan en el envase; null sin envase o sin inicio.
  Future<int?> remaining(SupplementRow s) async => remainingServings(
        servingsPerPack: s.servingsPerPack,
        start: s.startDate == null ? null : parseDay(s.startDate!),
        logDates: await _logDates(s.id),
      );

  /// Activos con lo que les queda.
  Future<List<SupplementStock>> stock() async => [
        for (final s in await all())
          if (s.active) SupplementStock(supplement: s, remaining: await remaining(s)),
      ];

  /// Constancia por suplemento en [from, to]: días con toma de los días
  /// desde su inicio (sin pasar de hoy).
  Future<Map<SupplementRow, ({int taken, int days})>> constancy(DateTime from, DateTime to, {DateTime? today}) async {
    final out = <SupplementRow, ({int taken, int days})>{};
    for (final s in await all()) {
      final c = supplementConstancy(
        start: s.startDate == null ? null : parseDay(s.startDate!),
        logDates: await _logDates(s.id),
        from: from,
        to: to,
        today: today ?? DateTime.now(),
      );
      if (c != null) out[s] = c;
    }
    return out;
  }

  /// El inicio de la creatina activa cuyas 4 semanas incluyen el día; null
  /// fuera de ellas. Con varias, la más reciente.
  Future<DateTime?> creatineWindowOn(DateTime day) async {
    DateTime? found;
    for (final s in await all()) {
      if (!s.active || s.startDate == null || !isCreatineName(s.name)) continue;
      final start = parseDay(s.startDate!);
      if (inCreatineWindow(start, day) && (found == null || start.isAfter(found))) found = start;
    }
    return found;
  }

  /// Las 4 semanas de cada creatina activa con inicio, para notas de peso.
  Future<List<({String name, DateTime start, DateTime end})>> creatineWindows() async => [
        for (final s in await all())
          if (s.active && s.startDate != null && isCreatineName(s.name))
            (
              name: s.name,
              start: creatineWindow(parseDay(s.startDate!)).start,
              end: creatineWindow(parseDay(s.startDate!)).end,
            ),
      ];

  /// Para el informe: todos los que tienen inicio, con todas sus tomas.
  Future<List<SupplementEntry>> entries() async => [
        for (final s in await all())
          SupplementEntry(
            name: s.name,
            start: s.startDate == null ? null : parseDay(s.startDate!),
            active: s.active,
            logs: (await _logDates(s.id)).toSet(),
          ),
      ];
}
