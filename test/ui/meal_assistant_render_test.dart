import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/features/meals/food_label_screen.dart';
import 'package:seguimiento/features/meals/meal_text_screen.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/meal_photo_fixture.dart';
import '../support/test_fonts.dart';

class _Activation extends AiActivation {
  @override
  Future<(String, String)> read() async =>
      ('SEG-FICTICIO', 'AAAA-BBBB-CCCC-DDDD');
}

http.Response _reply(String task, Object result) => http.Response(
      jsonEncode({
        'status': 'success',
        'contract': 2,
        'task': task,
        'model': 'gpt-6-luna',
        'result': result,
        'quota': {
          'remaining': 3,
          'limit': 4,
          'reset_at': '2026-10-07T00:00:00Z',
        }
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

ThemeData _theme() {
  final base = buildGymTheme();
  return base.copyWith(
    chipTheme: base.chipTheme.copyWith(
      labelStyle: base.chipTheme.labelStyle!.copyWith(fontFamily: 'Roboto'),
      secondaryLabelStyle:
          base.chipTheme.secondaryLabelStyle!.copyWith(fontFamily: 'Roboto'),
    ),
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle:
            base.appBarTheme.titleTextStyle!.copyWith(fontFamily: 'Roboto')),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style!.copyWith(
        textStyle: WidgetStatePropertyAll(base
            .filledButtonTheme.style!.textStyle!
            .resolve({})!.copyWith(fontFamily: 'Roboto')),
      ),
    ),
  );
}

void main() {
  final output = Platform.environment['AI_OUT'];
  for (final scale in [1.0, 1.6]) {
    for (final label in [false, true]) {
      testWidgets('captura IA ${label ? 'etiqueta' : 'frase'} $scale',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadTestFonts(tester);
        const boundaryKey = ValueKey('meal-ai-capture');
        final photo = fictionalPhoto();
        await tester.pumpWidget(RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _theme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: label
                ? FoodLabelScreen(
                    activation: _Activation(),
                    pickPhoto: (_) async => photo,
                    clientFactory: () => MockClient((request) async {
                      final task = (jsonDecode(request.body) as Map)['task'];
                      if (task == 'status') {
                        return _reply('status', {'enabled': true});
                      }
                      return _reply('food_label', {
                        'name': 'Bebida de prueba',
                        'basis': null,
                        'unit': null,
                        'serving_quantity': null,
                        'kcal': null,
                        'protein': null,
                        'carbs': null,
                        'fat': null,
                        'uncertainties': [
                          'Verifica la base y la energía del empaque.'
                        ],
                      });
                    }),
                  )
                : MealTextScreen(
                    foods: const [],
                    activation: _Activation(),
                    clientFactory: () => MockClient((request) async {
                      final task = (jsonDecode(request.body) as Map)['task'];
                      if (task == 'status') {
                        return _reply('status', {'enabled': true});
                      }
                      return _reply('meal_text', {
                        'items': [
                          {
                            'label': 'bebida de prueba',
                            'food_id': null,
                            'quantity': null,
                            'unit': null
                          }
                        ],
                        'uncertainties': ['Elige alimento y cantidad local.'],
                      });
                    }),
                  ),
          ),
        ));
        await tester.pumpAndSettle();
        if (label) {
          await tester.runAsync(() async {
            await tester.tap(find.text('Elegir foto'));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
          await tester.pumpAndSettle();
          final consent = find.byType(CheckboxListTile);
          await tester.scrollUntilVisible(consent, 130,
              scrollable: find.byType(Scrollable).first);
          await tester.ensureVisible(consent);
          await tester.pumpAndSettle();
          await tester.tap(consent);
          await tester.pumpAndSettle();
          final read = find.text('Leer etiqueta');
          await tester.scrollUntilVisible(read, 130,
              scrollable: find.byType(Scrollable).first);
          await tester.ensureVisible(read);
          await tester.pumpAndSettle();
          await tester.tap(read);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(find.text('Revisa lo leído'), 130,
              scrollable: find.byType(Scrollable).first);
        } else {
          await tester.enterText(find.byType(TextField).first, 'una bebida');
          await tester.pump();
          final consent = find.byType(CheckboxListTile);
          await tester.scrollUntilVisible(consent, 130,
              scrollable: find.byType(Scrollable).first);
          await tester.ensureVisible(consent);
          await tester.pumpAndSettle();
          await tester.tap(consent);
          await tester.pumpAndSettle();
          final analyze = find.text('Preparar borrador');
          await tester.scrollUntilVisible(analyze, 130,
              scrollable: find.byType(Scrollable).first);
          await tester.ensureVisible(analyze);
          await tester.pumpAndSettle();
          await tester.tap(analyze);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
              find.text('Revisa alimento y cantidad'), 130,
              scrollable: find.byType(Scrollable).first);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (output != null) {
          final boundary = tester
              .renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
          await tester.runAsync(() async {
            final picture = await boundary.toImage(pixelRatio: 2);
            try {
              final bytes =
                  await picture.toByteData(format: ui.ImageByteFormat.png);
              final directory = Directory(output)..createSync(recursive: true);
              final fileName =
                  label ? 'meal-label-$scale.png' : 'meal-text-$scale.png';
              await File('${directory.path}/$fileName')
                  .writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
            } finally {
              picture.dispose();
            }
          });
        }
      }, skip: output == null);
    }
  }
}
