import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/domain/recovery.dart' show sorenessZones;
import 'package:seguimiento/domain/warmup.dart';

import '../support/sqlite_host.dart';

/// Calentamiento (ADR 0015, revisión de Codex): la molestia guardada en
/// SQLite llega como aviso, sin ejercicio por zona.
void main() {
  setUpAll(useHostSqlite);

  test('SQLite -> molestias de hoy y ayer -> un aviso por zona sobre el umbral', () async {
    final db = openInMemoryDatabase();
    final recovery = RecoveryRepository(db);
    await recovery.setSoreness(DateTime(2026, 9, 23), {'Hombro': 5, 'Rodilla': 2});
    await recovery.setSoreness(DateTime(2026, 9, 20), {'Codo': 6});
    final byDay = await recovery.sorenessRange(DateTime(2026, 9, 24));
    final d0 = DateTime(2026, 9, 24);
    final zones = <String, int>{};
    for (final e in byDay.entries) {
      if (e.key.isBefore(d0.subtract(const Duration(days: 1)))) continue;
      for (final z in e.value.entries) {
        if (z.value > (zones[z.key] ?? 0)) zones[z.key] = z.value;
      }
    }
    final notes = soreWarmupNotes(zones, order: sorenessZones);
    expect(notes, hasLength(1), reason: 'codo es de hace 4 días; rodilla 2/10 no llega');
    expect(notes.single, startsWith('Molestia en hombro (5/10)'));
    await db.close();
  });
}
