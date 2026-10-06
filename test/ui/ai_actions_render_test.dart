import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/features/meals/meal_photo_screen.dart';
import 'package:seguimiento/features/report/weekly_ai_screen.dart';
import 'package:seguimiento/ui/theme.dart';
import '../support/meal_photo_fixture.dart';
import '../support/test_fonts.dart';

class _Activation extends AiActivation {
  @override
  Future<(String, String)> read() async =>
      ('SEG-FICTICIO', 'AAAA-BBBB-CCCC-DDDD');
  @override
  Future<void> save(String value) async {}
}

void main() {
  final output = Platform.environment['AI_OUT'];
  for (final scale in [1.0, 1.6]) {
    for (final photo in [false, true]) {
      testWidgets('captura IA ${photo ? 'comida' : 'respuesta'} $scale',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadTestFonts(tester);
        const key = ValueKey('capture');
        final base = buildGymTheme();
        final theme = base.copyWith(
          chipTheme: base.chipTheme.copyWith(
            labelStyle:
                base.chipTheme.labelStyle!.copyWith(fontFamily: 'Roboto'),
            secondaryLabelStyle: base.chipTheme.secondaryLabelStyle!
                .copyWith(fontFamily: 'Roboto'),
          ),
          textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
          appBarTheme: base.appBarTheme.copyWith(
              titleTextStyle: base.appBarTheme.titleTextStyle!
                  .copyWith(fontFamily: 'Roboto')),
          filledButtonTheme: FilledButtonThemeData(
              style: base.filledButtonTheme.style!.copyWith(
                  textStyle: WidgetStatePropertyAll(base
                      .filledButtonTheme.style!.textStyle!
                      .resolve({})!.copyWith(fontFamily: 'Roboto')))),
        );
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: photo
                  ? MealPhotoScreen(
                      activation: _Activation(),
                      pickPhoto: (_) async => fictionalPhoto(),
                      clientFactory: () => MockClient((request) async {
                            final body = jsonDecode(request.body) as Map;
                            if (body['task'] == 'status') {
                              return http.Response(
                                  jsonEncode({
                                    'status': 'success',
                                    'contract': 2,
                                    'task': 'status',
                                    'model': 'gpt-6-luna',
                                    'result': {'enabled': true},
                                    'quota': {
                                      'remaining': 3,
                                      'limit': 4,
                                      'reset_at': '2026-10-07T00:00:00Z'
                                    },
                                  }),
                                  200);
                            }
                            return http.Response(
                                jsonEncode(fictionalMeal()), 200);
                          }))
                  : WeeklyAiScreen(
                      report: 'Peso: sin registro',
                      activation: _Activation(),
                      clientFactory: () =>
                          MockClient((_) async => http.Response(
                              jsonEncode({
                                'model': 'gpt-6-luna',
                                'notes': [
                                  {
                                    'kind': 'missing',
                                    'text':
                                        'Falta el registro de peso para comparar la semana.',
                                    'quote': 'Peso: sin registro'
                                  }
                                ]
                              }),
                              200))),
            )));
        await tester.pumpAndSettle();
        if (photo) {
          await tester.runAsync(() async {
            await tester.tap(find.text('Elegir foto'));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pumpAndSettle();
        }
        await tester.scrollUntilVisible(find.byType(CheckboxListTile), 160,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        final send = find.text(photo ? 'Analizar foto' : 'Enviar y analizar');
        await tester.scrollUntilVisible(send, 130,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(send);
        await tester.pumpAndSettle();
        final target = find.text(photo
            ? 'Revisa la propuesta'
            : 'Comentarios de IA · verifica la evidencia');
        await tester.scrollUntilVisible(target, 150,
            scrollable: find.byType(Scrollable).first);
        await tester.drag(find.byType(ListView).first, const Offset(0, -160));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
        await tester.runAsync(() async {
          final picture = await boundary.toImage(pixelRatio: 2);
          final bytes =
              await picture.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory(output!)..createSync(recursive: true);
          File('${directory.path}/${photo ? 'comida' : 'respuesta'}-$scale.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }, skip: output == null);
    }
  }
}
