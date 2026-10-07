import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/corrections_29sep.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/history_import.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/sqlite_host.dart';

/// Traspaso del 7 oct: historial del 26 ago al 21 sep y metas del v3.1 (§16.16).
void main() {
  late AppDatabase db;
  late TrainingRepository training;

  setUpAll(useHostSqlite);

  setUp(() async {
    db = openInMemoryDatabase();
    training = TrainingRepository(db, ExerciseRepository(db));
    await db.into(db.profiles).insert(ProfilesCompanion.insert(startDate: '2026-09-22'));
  });

  tearDown(() => db.close());

  DataCorrection byId(String id) => corrections7Oct.firstWhere((c) => c.id == id);

  test('el historial trae 27 entradas: 19 sesiones y 8 días de fútbol', () {
    expect(historyAugSep, hasLength(27));
    expect(historyAugSep.where((e) => e.kind == 'futbol'), hasLength(8));
  });

  test('importarlo marca todo como importado y no repite al aplicarlo otra vez', () async {
    final history = byId('historial-ago-sep');
    expect(await history.check(db), CorrectionState.pending);
    await history.apply(db);
    expect(await history.check(db), CorrectionState.done);
    await history.apply(db);

    final sessions = await db.select(db.sessions).get();
    final games = await db.select(db.footballGames).get();
    expect(sessions, hasLength(19));
    expect(games, hasLength(8));
    expect(sessions.every((s) => s.imported), isTrue);
    expect(games.every((g) => g.imported && g.minutes == 0), isTrue);
    expect(await firstDataDay(db), DateTime(2026, 8, 26));

    final sep11 = sessions.firstWhere((s) => s.date == '2026-09-11');
    expect(sep11.type, SessionType.progresion);
    expect(sep11.roundsDone, 7);
    final early = sessions.firstWhere((s) => s.date == '2026-08-26');
    expect(early.type, SessionType.otro, reason: 'sin detalle: no es circuito ni marca');
  });

  test('lo importado no es récord; lo registrado en la app sí', () async {
    await byId('historial-ago-sep').apply(db);
    expect(await training.bestRounds(), isNull, reason: 'las 7 rondas importadas no son marca');
    await training.save(SessionDraft(date: DateTime(2026, 9, 25), type: SessionType.progresion, roundsDone: 6));
    expect(await training.bestRounds(), 6);
  });

  test('un día ya registrado en la app no se llena con el historial', () async {
    await training.save(SessionDraft(date: DateTime(2026, 9, 21), type: SessionType.circuito, roundsDone: 5));
    await byId('historial-ago-sep').apply(db);
    final sep21 = await (db.select(db.sessions)..where((t) => t.date.equals('2026-09-21'))).get();
    expect(sep21, hasLength(1));
    expect(sep21.single.imported, isFalse);
  });

  test('metas del v3.1 desde ya', () async {
    final goals = byId('metas-v31');
    expect(await goals.check(db), CorrectionState.pending);
    await goals.apply(db);
    expect(await goals.check(db), CorrectionState.done);
    final p = await (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingle();
    expect((p.kcalTarget, p.kcalTargetFootball, p.proteinMin, p.proteinMax), (2100, 2400, 160, 170));
  });
}
