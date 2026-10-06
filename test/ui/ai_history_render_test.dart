import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/data/repositories/ai_conversation_repository.dart';
import 'package:seguimiento/domain/ai_context.dart';
import 'package:seguimiento/features/ai/ai_conversation_screen.dart';
import 'package:seguimiento/features/ai/ai_history_screen.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

class _Activation extends AiActivation {
  @override
  Future<(String, String)> read() async =>
      ('SEG-FICTICIO', 'AAAA-BBBB-CCCC-DDDD');
}

void main() {
  setUpAll(useHostSqlite);
  final output = Platform.environment['AI_HISTORY_OUT'];

  for (final scale in [1.0, 1.6]) {
    for (final history in [false, true]) {
      testWidgets('captura IA ${history ? 'historial' : 'pregunta'} $scale',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadTestFonts(tester);
        final db = openInMemoryDatabase();
        final repo = AiConversationRepository(db);
        final snapshot = AiConversationSnapshot(
          kind: AiConversationKind.reportQuestion,
          title: 'Informe · 5–11 oct',
          rangeStart: DateTime(2026, 10, 5),
          rangeEnd: DateTime(2026, 10, 11),
          sources: const [
            AiContextSource(
              id: 'report',
              title: 'Resumen del informe',
              text: 'Sesiones completadas y comidas registradas en el rango.',
            ),
          ],
          model: aiQuestionModel,
          contractVersion: aiQuestionContractVersion,
        );
        if (history) {
          await repo.createValidatedConversation(
            snapshot: snapshot,
            question: '¿Qué destaca del rango?',
            answer: 'Las sesiones y comidas aparecen en la fuente.',
            citations: const [
              AiCitation(sourceId: 'report', quote: 'Sesiones completadas')
            ],
            turnModel: aiQuestionModel,
            turnContractVersion: aiQuestionContractVersion,
          );
        }
        const captureKey = ValueKey('ai-history-capture');
        final base = buildGymTheme();
        final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
          appBarTheme: base.appBarTheme.copyWith(
            titleTextStyle:
                base.appBarTheme.titleTextStyle!.copyWith(fontFamily: 'Roboto'),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: base.filledButtonTheme.style!.copyWith(
              textStyle: WidgetStatePropertyAll(base
                  .filledButtonTheme.style!.textStyle!
                  .resolve({})!.copyWith(fontFamily: 'Roboto')),
            ),
          ),
        );
        await tester.pumpWidget(RepaintBoundary(
          key: captureKey,
          child: ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: history
                  ? const AiHistoryScreen()
                  : AiConversationScreen.forQuestion(
                      repository: repo,
                      snapshot: snapshot,
                      activation: _Activation(),
                      clientFactory: () => MockClient((request) async {
                        expect((jsonDecode(request.body) as Map)['task'],
                            'status');
                        return http.Response(
                            jsonEncode({
                              'status': 'success',
                              'contract': 2,
                              'task': 'status',
                              'model': 'gpt-6-luna',
                              'result': {'enabled': true},
                              'quota': {
                                'remaining': 19,
                                'limit': 20,
                                'reset_at': '2026-10-07T00:00:00Z'
                              },
                            }),
                            200);
                      }),
                    ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (output != null) {
          final boundary = tester
              .renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
          await tester.runAsync(() async {
            final picture = await boundary.toImage(pixelRatio: 2);
            try {
              final bytes =
                  await picture.toByteData(format: ui.ImageByteFormat.png);
              final directory = Directory(output)..createSync(recursive: true);
              await File(
                      '${directory.path}/${history ? 'historial' : 'pregunta'}-$scale.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              picture.dispose();
            }
          });
        }
        await db.close();
      }, skip: output == null);
    }
  }
}
