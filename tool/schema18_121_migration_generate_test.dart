// Run only against the frozen 1.20.0 source checkout; never against 1.21.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/ai_conversation_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/domain/ai_context.dart';

import '../test/support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test('freeze genuine populated schema 18 with synthetic data', () async {
    final output = Platform.environment['SCHEMA18_OUTPUT'];
    if (output == null) throw StateError('SCHEMA18_OUTPUT is required');
    final file = File(output);
    if (file.existsSync()) throw StateError('Refuse to overwrite fixture');
    final db = AppDatabase(NativeDatabase(file));
    try {
      expect(db.schemaVersion, 18, reason: 'requires genuine 1.20 source');
      await db.customStatement('SELECT 1');
      await ReminderRepository(db).ensureDefaults();
      await db.customStatement(
          "UPDATE reminders SET enabled=0, hour=14, minute=15 WHERE kind='sesion'");
      await db.customStatement(
          "UPDATE profiles SET start_date = '2026-09-28', height_cm = 175, protein_min = 160, protein_max = 170, kcal_target = 2100 WHERE id = 1");
      await db.customStatement(
          "INSERT INTO exercises(id,name,form_cues,tracks_load) VALUES(901,'Dominadas QA','Escápulas activas',1)");
      await db.customStatement(
          "INSERT INTO sessions(id,date,start_time,type,total_sec,warmup_sec,cooldown_sec,rest_sec,rounds_done,rpe,context,notes,technique_ok,full_range,recovery_ok) VALUES(902,'2026-10-05','07:20','bloques',1500,360,180,300,3,7,'QA sintética: fuente18','No representa datos de una persona',1,1,1)");
      await db.customStatement(
          'INSERT INTO session_sets(id,session_id,exercise_id,set_index,reps,load_kg,rir) VALUES(903,902,901,1,8,4.5,2)');
      await db.customStatement(
          "INSERT INTO meals(id,date,time,slot,notes) VALUES(904,'2026-10-05','08:10','desayuno','Comida QA sintética')");
      await db.customStatement(
          "INSERT INTO meal_items(id,meal_id,label,quantity,quantity_unit,kcal,protein,carbs,fat,source_verified) VALUES(905,904,'Plato QA',1,'porción',450,30,45,15,0)");
      await db.customStatement(
          "INSERT INTO body_weights(id,date,kg,fasted,moment,time) VALUES(906,'2026-10-05',72.5,1,'ayunas','06:50')");
      final repository = AiConversationRepository(db);
      final report = AiConversationSnapshot(
        kind: AiConversationKind.reportQuestion,
        title: 'QA · informe sintético',
        rangeStart: DateTime(2026, 9, 28),
        rangeEnd: DateTime(2026, 10, 5),
        sources: const [
          AiContextSource(
              id: 'report',
              title: 'Informe QA',
              text:
                  'Sesión QA: 3 series. Comida QA: 450 kcal. Peso QA: 72,5 kg.'),
          AiContextSource(
              id: 'prior_report',
              title: 'Periodo previo QA',
              text:
                  'Registro previo QA incompleto. No permite concluir una tendencia.'),
        ],
        model: aiQuestionModel,
        contractVersion: aiQuestionContractVersion,
      );
      final reportId = await repository.createValidatedConversation(
        snapshot: report,
        question: '¿Qué está registrado?',
        answer:
            'La fuente registra sesión, comida y peso; el periodo previo está incompleto.',
        citations: const [
          AiCitation(sourceId: 'report', quote: 'Sesión QA: 3 series.'),
          AiCitation(
              sourceId: 'prior_report', quote: 'Registro previo QA incompleto.')
        ],
        turnModel: aiQuestionModel,
        turnContractVersion: aiQuestionContractVersion,
        createdAt: DateTime.utc(2026, 10, 6, 12),
      );
      expect(reportId, 1);
      await repository.appendValidatedTurn(
        conversationId: reportId,
        question: '¿Hay evidencia de tendencia?',
        answer: 'La fuente previa no permite concluir una tendencia.',
        citations: const [
          AiCitation(
              sourceId: 'prior_report',
              quote: 'No permite concluir una tendencia.')
        ],
        createdAt: DateTime.utc(2026, 10, 6, 12, 1),
      );
      final guide = AiConversationSnapshot(
        kind: AiConversationKind.exerciseQuestion,
        title: 'QA · guía Dominadas',
        sources: const [
          AiContextSource(
              id: 'exercise_guide:dominadas',
              title: 'Guía QA',
              text: 'Dominadas con carga y agarre prona. Escápulas activas.')
        ],
        model: aiQuestionModel,
        contractVersion: aiQuestionContractVersion,
        guideContext: AiGuideContext(
            exercise: 'Dominadas',
            cues: ['Escápulas activas'],
            progressionNote: 'Mantén la variante elegida.',
            grip: 'prona',
            loaded: true),
      );
      expect(
          await repository.createValidatedConversation(
            snapshot: guide,
            question: '¿Qué variante corresponde?',
            answer: 'La guía corresponde a dominadas con carga y agarre prona.',
            citations: const [
              AiCitation(
                  sourceId: 'exercise_guide:dominadas',
                  quote: 'Dominadas con carga y agarre prona.')
            ],
            turnModel: aiQuestionModel,
            turnContractVersion: aiQuestionContractVersion,
            createdAt: DateTime.utc(2026, 10, 6, 12, 2),
          ),
          2);
      expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          18);
      expect(await repository.count(), 2);
    } finally {
      await db.close();
    }
    final reopened = AppDatabase(NativeDatabase(file));
    try {
      final repo = AiConversationRepository(reopened);
      expect((await repo.read(1))!.turns, hasLength(4));
      expect((await repo.read(2))!.snapshot.guideContext!.grip, 'prona');
    } finally {
      await reopened.close();
    }
  });
}
