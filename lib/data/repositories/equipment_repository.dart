import 'package:drift/drift.dart';

import '../../domain/equipment.dart';
import '../../domain/fitness_test.dart' show TestPart, testItem;
import '../database.dart';
import '../local_flags.dart';
import 'plan_repository.dart';

/// Prueba no hecha por falta de material que ya se puede hacer: todo lo que
/// pedía está en `tengo` y no se midió en un intento posterior del mismo
/// protocolo (plan 052, §16.27.4).
class PendingEquipmentTest {
  const PendingEquipmentTest(
      {required this.pending, required this.attempt, required this.requires});

  final TestPendingRow pending;
  final FitnessTestAttempt attempt;

  /// Claves del material que pedía (`mat`).
  final List<String> requires;

  String get itemName => testItem(pending.item)?.name ?? pending.item;

  TestPart? get part =>
      TestPart.values.where((p) => p.name == attempt.part).firstOrNull;

  /// "colchoneta", "colchoneta y anillas".
  String get requiresLabel => requires
      .map((k) => equipmentItem(k)?.short ?? k)
      .join(' y ');
}

/// Material del usuario (plan 052, §16.27.4). Para mini paralelas y anillas
/// el inventario manda y las banderas locales lo siguen: el resto de la app
/// (Plan, escaleras, Hoy) sigue leyendo `hasParallettes`/`hasRings`.
class EquipmentRepository {
  EquipmentRepository(this.db, {this.flags});

  final AppDatabase db;

  /// Sin banderas (pruebas, lecturas de Hoy) los estados por omisión de
  /// paralelas y anillas salen de lo que se pase o quedan en `no_tengo`.
  final LocalFlags? flags;

  /// Bandera local que sigue a `key`, si la hay.
  static String? flagFor(String key) => switch (key) {
        EquipmentKeys.parallettes => FlagKeys.hasParallettes,
        EquipmentKeys.rings => FlagKeys.hasRings,
        _ => null,
      };

  Future<Map<String, EquipmentRow>> rows() async => {
        for (final r in await db.select(db.equipmentItems).get()) r.key: r,
      };

  Stream<List<EquipmentRow>> watchRows() =>
      db.select(db.equipmentItems).watch();

  /// Estado sin fila guardada: el del catálogo; paralelas y anillas, de su
  /// bandera (`flag` si se pasa; si no, la bandera local). Nunca `tengo` sin
  /// que el usuario lo haya dicho.
  String defaultStatus(String key, {bool? flag}) {
    if (equipmentItem(key)?.defaultStatus case final status?) return status;
    final flagKey = flagFor(key);
    final has = flag ?? (flagKey == null ? null : flags?.get<bool>(flagKey));
    return has == true ? EquipmentStatus.tengo : EquipmentStatus.noTengo;
  }

  /// Estado de todo el catálogo. `parallettes`/`rings`: lo que dicen las
  /// banderas en quien llama (Hoy y el cronómetro ya las leyeron); sólo se
  /// usan cuando no hay fila.
  Future<Map<String, String>> statuses({bool? parallettes, bool? rings}) async {
    final stored = await rows();
    return {
      for (final item in equipmentCatalog)
        item.key: stored[item.key]?.status ??
            defaultStatus(item.key,
                flag: switch (item.key) {
                  EquipmentKeys.parallettes => parallettes,
                  EquipmentKeys.rings => rings,
                  _ => null,
                }),
    };
  }

  /// Guarda el estado (y los kg de la mochila). Paralelas y anillas
  /// actualizan su bandera después de la base: `tengo` → true; si no, false.
  Future<void> set(String key, String status, {double? kg}) async {
    if (equipmentItem(key) == null) {
      throw ArgumentError.value(key, 'key', 'Material desconocido');
    }
    if (!EquipmentStatus.all.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Estado inválido');
    }
    await db.into(db.equipmentItems).insertOnConflictUpdate(
        EquipmentItemsCompanion.insert(key: key, status: status, kg: Value(kg)));
    final flag = flagFor(key);
    final local = flags;
    if (flag != null && local != null) {
      await local.set(flag, status == EquipmentStatus.tengo);
    }
  }

  /// El interruptor de Plan cambió: el inventario lo registra. Apagarlo
  /// conserva "en compra" si ya estaba así.
  Future<void> setFromToggle(String key, bool has) async {
    final current = (await rows())[key];
    final status = has
        ? EquipmentStatus.tengo
        : current?.status == EquipmentStatus.enCompra
            ? EquipmentStatus.enCompra
            : EquipmentStatus.noTengo;
    await set(key, status, kg: current?.kg);
  }

  /// Las banderas viven fuera de la base: tras restaurar un respaldo pueden
  /// no coincidir con el inventario. Las filas guardadas mandan.
  Future<void> syncFlagsFromInventory() async {
    final local = flags;
    if (local == null) return;
    final stored = await rows();
    for (final key in [EquipmentKeys.parallettes, EquipmentKeys.rings]) {
      final row = stored[key];
      if (row == null) continue;
      final has = row.status == EquipmentStatus.tengo;
      if (local.get<bool>(flagFor(key)!) != has) {
        await local.set(flagFor(key)!, has);
      }
    }
  }

  /// Pruebas pendientes por material que ya está (`tengo`) y que todavía no
  /// se midieron en un intento posterior del mismo protocolo.
  Future<List<PendingEquipmentTest>> pendingReadyForEquipment() async {
    final pending = await (db.select(db.fitnessTestPending)
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    if (pending.isEmpty) return const [];
    final current = await statuses();
    final out = <PendingEquipmentTest>[];
    for (final p in pending) {
      final requires = equipmentRequires(p.requires);
      if (requires.isEmpty ||
          requires.any((k) =>
              equipmentStatusOf(k, current) != EquipmentStatus.tengo)) {
        continue;
      }
      final attempt = await (db.select(db.fitnessTestAttempts)
            ..where((t) => t.id.equals(p.attemptId)))
          .getSingleOrNull();
      if (attempt == null || await _measuredAfter(p.item, attempt)) continue;
      out.add(PendingEquipmentTest(
          pending: p, attempt: attempt, requires: requires));
    }
    return out;
  }

  /// ¿Hay un resultado de `item` en un intento posterior del mismo protocolo?
  Future<bool> _measuredAfter(String item, FitnessTestAttempt attempt) async {
    final later = [
      for (final a in await (db.select(db.fitnessTestAttempts)
            ..where((t) => t.protocolId.equals(attempt.protocolId)))
          .get())
        if (a.id > attempt.id) a.id
    ];
    if (later.isEmpty) return false;
    final rows = await (db.select(db.fitnessTests)
          ..where((t) => t.item.equals(item) & t.attemptId.isIn(later))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }
}

/// El día después de mirar el material: lo que salió (una nota por
/// ejercicio) queda en `pending`.
class EquipmentApplied {
  const EquipmentApplied(this.day, {this.pending = const []});

  final PlanDayDraft day;

  /// "Pino pecho a la pared pendiente: falta colchoneta."
  final List<String> pending;
}

/// Único filtro de material para un día compuesto (v3.1/v3.2 y planes sin
/// bloques). Sin el material obligatorio el ejercicio sale con una nota en el
/// día (o se queda con su alternativa); sin el recomendado se queda con
/// "Mejor con …". No toca el día recibido: devuelve uno nuevo si cambia.
EquipmentApplied applyEquipmentDetailed(
    PlanDayDraft day, Map<String, String> statuses) {
  final kept = <PlanExerciseDraft>[];
  final pending = <String>[];
  var changed = false;
  for (final e in day.exercises) {
    final check =
        checkEquipment(e.name, statuses, variantKey: e.physicalVariantKey);
    if (check.blocked) {
      changed = true;
      final note =
          equipmentPendingNote(e.name, check.missingRequired, statuses);
      if (!pending.contains(note)) pending.add(note);
      continue;
    }
    final extra = [
      for (final n in check.notes)
        if (!(e.notes ?? '').contains(n)) n
    ];
    if (extra.isEmpty) {
      kept.add(e);
      continue;
    }
    changed = true;
    kept.add(e.copyWith()
      ..notes = [
        if (e.notes != null && e.notes!.trim().isNotEmpty) e.notes!,
        ...extra,
      ].join(' · '));
  }
  if (!changed) return EquipmentApplied(day);
  final notes = [
    if (day.notes != null && day.notes!.trim().isNotEmpty) day.notes!,
    ...pending,
  ];
  return EquipmentApplied(
      PlanDayDraft(
          weekday: day.weekday,
          type: day.type,
          targetRounds: day.targetRounds,
          restBetweenRoundsSec: day.restBetweenRoundsSec,
          notes: notes.isEmpty ? null : notes.join(' · '),
          exercises: kept,
          coreEpochs: day.coreEpochs),
      pending: pending);
}

PlanDayDraft applyEquipment(PlanDayDraft day, Map<String, String> statuses) =>
    applyEquipmentDetailed(day, statuses).day;
