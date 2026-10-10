import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/coach_repository.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/domain/adaptive_coach.dart';
import 'package:seguimiento/domain/goal_history.dart';

import '../support/sqlite_host.dart';

/// Plan 009, R2: ZIP → restaurar en otra instalación → cerrar y reabrir. Las
/// vigencias (legado, conocidas, futura) y las decisiones aceptadas,
/// pospuestas y rechazadas vuelven exactas, y la lectura de Hoy es la misma.
void main() {
  setUpAll(() {
    useHostSqlite();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  DateTime d(int month, int day) => DateTime(2026, month, day);
  final monday = d(11, 2);

  late Directory root;
  late DatabaseHost a;
  late DatabaseHost b;

  setUp(() {
    root = Directory.systemTemp.createTempSync('seguimiento_coach_backup_');
    final dirA = Directory('${root.path}/A')..createSync();
    final dirB = Directory('${root.path}/B')..createSync();
    a = DatabaseHost(File('${dirA.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
    b = DatabaseHost(File('${dirB.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
  });

  tearDown(() async {
    await a.db.close();
    await b.db.close();
    root.deleteSync(recursive: true);
  });

  Future<List<Map<String, Object?>>> rows(AppDatabase db, String table) async =>
      [for (final r in await db.customSelect('select * from $table order by rowid').get()) r.data];

  test('vigencias y decisiones exactas tras ZIP, restauración y reapertura', () async {
    final db = a.db;
    final goals = GoalRepository(db);
    // Vigencias: legado sin fecha, conocida desde septiembre, una aceptada
    // desde propuesta y una futura todavía sin regir.
    await db.delete(db.goalVersions).go();
    await db.into(db.goalVersions).insert(GoalVersionsCompanion.insert(
        metric: GoalMetric.pasos.name, value: const Value(7500), acceptedAt: '2026-08-01', origin: GoalOrigin.legado));
    await db.into(db.goalVersions).insert(GoalVersionsCompanion.insert(
        metric: GoalMetric.pasos.name,
        value: const Value(5000),
        effectiveFrom: const Value('2026-09-01'),
        acceptedAt: '2026-09-01',
        origin: GoalOrigin.inicio));
    await goals.scheduleGoal(GoalMetric.proteinaMin, 140,
        effectiveFrom: d(10, 20), origin: GoalOrigin.perfil, reason: 'Ajustes', now: d(10, 19));
    await goals.scheduleGoal(GoalMetric.pasos, 6000, effectiveFrom: d(11, 2), origin: GoalOrigin.propuesta, now: d(11, 1));
    await goals.scheduleGoal(GoalMetric.proteinaMin, 150, effectiveFrom: d(12, 1), origin: GoalOrigin.perfil, now: d(11, 1));
    await goals.setReference(GoalMetric.refDominadas, 8, now: d(10, 5));

    // Decisiones: pasos aceptada con su cifra, fuerza aceptada con la dosis,
    // rondas pospuesta con su fecha, escalera rechazada.
    await db.into(db.coachProposals).insert(CoachProposalsCompanion.insert(
        id: 'pasos:5000>6000:2026-09-01:p1',
        kind: 'pasos',
        status: ProposalStatus.aceptada.name,
        evidence: '10 de 10 días entre semana con pasos · promedio 6.490',
        createdOn: '2026-11-01',
        decidedOn: const Value('2026-11-01'),
        acceptedValue: const Value(6000),
        policy: const Value(coachPolicy)));
    const dose = StrengthDose(kind: DoseKind.carga, sessionId: 41, fromLoadKg: 0, sets: 4, repsMin: 6, planDayId: 7);
    await goals.decideProposal(strengthProposalId('Fondos en barra', 41), strengthProposalKind('Fondos en barra'),
        ProposalStatus.aceptada,
        today: d(10, 20), evidence: dose.encode());
    await goals.decideProposal(roundsProposalId(fromRounds: 8, toRounds: 9, sessionId: 7), 'rondas', ProposalStatus.pospuesta,
        today: d(11, 2), postponeDays: coachPostponeDays);
    await goals.decideProposal(ladderProposalId('v_up', 1, d(10, 15)), 'escalera:v_up', ProposalStatus.rechazada,
        today: d(10, 29));

    // Lo que alimenta la lectura de Hoy.
    final w = coachWindow(monday);
    for (var i = 0; i < w.length; i++) {
      await StepsRepository(db).setSteps(w[i], 6400 + i * 20);
    }
    await RecoveryRepository(db).setFeeling(d(11, 1), 2);

    final goalsBefore = await rows(db, 'goal_versions');
    final proposalsBefore = await rows(db, 'coach_proposals');
    final feelingsBefore = await rows(db, 'morning_checks');
    final readingBefore = await CoachRepository(db).stepsReading(monday);
    expect(goalsBefore, hasLength(6));
    expect(proposalsBefore, hasLength(4));

    final zip = await BackupArchive(host: a, documents: a.file.parent).exportTo('${root.path}/respaldo.zip');
    await BackupArchive(host: b, documents: b.file.parent).restoreFrom(zip.file);

    // Reapertura: otra conexión sobre el archivo restaurado, como al abrir la app.
    await b.db.close();
    b = DatabaseHost(b.file, (f) => AppDatabase(NativeDatabase(f)));
    final rb = b.db;
    expect(await rows(rb, 'goal_versions'), goalsBefore, reason: 'vigencias exactas, con origen, fecha y razón');
    expect(await rows(rb, 'coach_proposals'), proposalsBefore, reason: 'decisiones exactas');
    expect(await rows(rb, 'morning_checks'), feelingsBefore);

    final h = await GoalRepository(rb).history();
    expect(h.on(GoalMetric.pasos, d(8, 20))!.known, isFalse, reason: 'el legado sigue siendo meta no registrada');
    expect(h.on(GoalMetric.pasos, d(11, 1))!.value, 5000);
    expect(h.on(GoalMetric.pasos, d(11, 2))!.value, 6000, reason: 'la aceptada rige desde el día siguiente a decidir');
    expect(h.on(GoalMetric.proteinaMin, d(11, 30))!.value, 140);
    expect(h.on(GoalMetric.proteinaMin, d(12, 1))!.value, 150, reason: 'la futura sigue futura y llega en su día');
    expect(h.current(GoalMetric.refDominadas, d(11, 2))!.value, 8);

    final restoredGoals = GoalRepository(rb);
    final strength = (await restoredGoals.lastDecision(strengthProposalKind('Fondos en barra')))!;
    expect(StrengthDose.decode(strength.$2.evidence)!.toJson(), dose.toJson(), reason: 'la dosis aceptada vuelve estructurada');
    final rounds = (await restoredGoals.proposal(roundsProposalId(fromRounds: 8, toRounds: 9, sessionId: 7)))!;
    expect((rounds.status, rounds.reviewAfter), (ProposalStatus.pospuesta, d(11, 9)));
    expect(proposalHidden(rounds, d(11, 8)), isTrue);
    expect(proposalHidden(rounds, d(11, 9)), isFalse);
    expect((await restoredGoals.proposal(ladderProposalId('v_up', 1, d(10, 15))))!.status, ProposalStatus.rechazada);

    final readingAfter = await CoachRepository(rb).stepsReading(monday);
    expect((readingAfter.state, readingAfter.reason, readingAfter.nextReview),
        (readingBefore.state, readingBefore.reason, readingBefore.nextReview));
    expect(readingAfter.evidence, readingBefore.evidence);
    expect(readingAfter.reason, 'Meta de 6.000 desde el 2 nov: se revisa el 16 nov.',
        reason: 'la vigencia aceptada sigue en prueba, sin volver a proponer');
  });
}
