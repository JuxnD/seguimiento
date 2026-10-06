import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/ai_conversation_repository.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/domain/ai_context.dart';
import 'package:seguimiento/domain/ai_report_sources.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/report/missing_data_actions.dart';
import 'package:seguimiento/domain/report/report_input.dart';
import 'package:seguimiento/features/ai/ai_conversation_screen.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';

class _Activation extends AiActivation {
  @override
  Future<(String, String)> read() async => ('SEG-FICTICIO', '');

  @override
  Future<void> save(String value) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Android: historial conserva snapshot y fecha al reabrir y viajar en ZIP',
      (tester) async {
    final root =
        await Directory.systemTemp.createTemp('seguimiento-ai-history-');
    final aDir = await Directory('${root.path}/A').create();
    final bDir = await Directory('${root.path}/B').create();
    final aFile = File('${aDir.path}/seguimiento.sqlite');
    final a = DatabaseHost(aFile, (file) => AppDatabase(NativeDatabase(file)));
    final b = DatabaseHost(File('${bDir.path}/seguimiento.sqlite'),
        (file) => AppDatabase(NativeDatabase(file)));
    try {
      await a.db.customStatement('select 1');
      const sourceText =
          'Dominadas: prona, con carga. Escápulas activas. Conserva la progresión indicada.';
      final snapshot = AiConversationSnapshot(
        kind: AiConversationKind.exerciseQuestion,
        title: 'Guía · Dominadas · 10 kg',
        rangeStart: DateTime(2026, 10, 5),
        rangeEnd: DateTime(2026, 10, 11),
        sources: [
          const AiContextSource(
            id: 'exercise_guide:dominadas',
            title: 'Guía seleccionada · Dominadas',
            text: sourceText,
          ),
        ],
        model: aiQuestionModel,
        contractVersion: aiQuestionContractVersion,
        guideContext: AiGuideContext(
          exercise: 'Dominadas',
          cues: const ['Escápulas activas'],
          progressionNote: 'Conserva la progresión indicada.',
          grip: 'prona',
          loaded: true,
        ),
      );
      final savedId =
          await AiConversationRepository(a.db).createValidatedConversation(
        snapshot: snapshot,
        question: '¿Qué debo cuidar en este movimiento?',
        answer: 'Mantén las escápulas activas durante el movimiento.',
        citations: const [
          AiCitation(
              sourceId: 'exercise_guide:dominadas',
              quote: 'Dominadas: prona, con carga.')
        ],
        turnModel: aiQuestionModel,
        turnContractVersion: aiQuestionContractVersion,
      );

      final archive = await BackupArchive(host: a, documents: aDir)
          .exportTo('${root.path}/historial-sintetico.zip');
      expect(archive.complete, isTrue);
      await a.db.close();

      // Cierre y reapertura simulan el siguiente arranque de la aplicación.
      final reopened =
          DatabaseHost(aFile, (file) => AppDatabase(NativeDatabase(file)));
      try {
        final localRecord =
            await AiConversationRepository(reopened.db).read(savedId);
        expect(localRecord!.snapshot.rangeStart, DateTime(2026, 10, 5));
        expect(localRecord.snapshot.sources.single.text, sourceText);
        expect(localRecord.turns.last.citations.single.quote,
            'Dominadas: prona, con carga.');
        expect(localRecord.snapshot.guideContext?.grip, 'prona');
        expect(localRecord.snapshot.guideContext?.loaded, isTrue);
      } finally {
        await reopened.db.close();
      }

      await b.db.customStatement('select 1');
      await BackupArchive(host: b, documents: bDir).restoreFrom(archive.file);
      final imported = await AiConversationRepository(b.db).read(savedId);
      expect(imported!.snapshot.title, 'Guía · Dominadas · 10 kg');
      expect(imported.snapshot.rangeEnd, DateTime(2026, 10, 11));
      expect(imported.snapshot.sourceHash, snapshot.sourceHash);
      expect(imported.snapshot.guideContext?.progressionNote,
          'Conserva la progresión indicada.');
      expect(imported.turns, hasLength(2));

      await tester.pumpWidget(ProviderScope(
          overrides: [databaseProvider.overrideWithValue(b.db)],
          child: MaterialApp(
              home: Builder(
                  builder: (context) => Scaffold(
                        body: TextButton(
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AiConversationScreen.forConversation(
                                repository: AiConversationRepository(b.db),
                                conversationId: savedId,
                                activation: _Activation(),
                              ),
                            ),
                          ),
                          child: const Text('Abrir historial sintético'),
                        ),
                      )))));
      await tester.tap(find.text('Abrir historial sintético'));
      await tester.pumpAndSettle();
      final openGuide = find.text('Ver guía completa');
      await tester.ensureVisible(openGuide);
      await tester.tap(openGuide);
      await tester.pumpAndSettle();
      expect(find.text('Dominadas'), findsWidgets);
      final figure =
          tester.widget<ExerciseFigureView>(find.byType(ExerciseFigureView));
      expect(figure.grip, 'prona');
      expect(figure.loaded, isTrue);
      // La variante vive en el visor, no en un Text aislado llamado "prona".
      // El asset se lee por IO real y las filas inferiores son perezosas.
      for (var wait = 0;
          wait < 100 && find.byType(Figure3DMoments).evaluate().isEmpty;
          wait++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(Figure3DMoments), findsOneWidget);
      final guideScroll = find
          .byWidgetPredicate((widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down)
          .last;
      await tester.scrollUntilVisible(find.text('Escápulas activas'), 140,
          scrollable: guideScroll);
      expect(find.text('Escápulas activas'), findsWidgets);
      final loadedCue = find.text(
          'Si va con mochila: correas ajustadas y el peso envuelto en una toalla para que no se mueva.');
      await tester.scrollUntilVisible(loadedCue, -140, scrollable: guideScroll);
      expect(loadedCue, findsOneWidget);
      expect(tester.takeException(), isNull);

      final input = ReportInput(
        programStart: DateTime(2026, 9, 1),
        rangeStart: DateTime(2026, 10, 5),
        rangeEnd: DateTime(2026, 10, 11),
        today: DateTime(2026, 10, 11),
        sessions: const [],
        meals: const [],
        weightsInRange: const [],
        measurementsInRange: const [],
        notes: '',
        steps: const {},
        sleep: const {},
      );
      final weighIn = missingDataActions(input)
          .firstWhere((action) => action.kind == ReportActionKind.weighIn);
      expect(dayKey(weighIn.date), '2026-10-11');
      expect(reportQuestionSources(input: input, report: 'Informe ficticio'),
          hasLength(1));
    } finally {
      await b.db.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
