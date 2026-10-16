import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/watch_capture.dart';
import 'package:seguimiento/features/training/watch_activity_card.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/test_fonts.dart';

/// Plan 058 (§16.17): el formulario de los datos del reloj (el que confirma
/// lo leído de la captura o se llena a mano). Guardar en la base lo cubre
/// test/data/plan058_reloj_test.dart.
void main() {
  Future<List<WatchReading?>> open(WidgetTester tester,
      {WatchReading? initial, bool vitals = false}) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadTestFonts(tester);
    final results = <WatchReading?>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildGymTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results
                .add(await editWatchReading(context, initial: initial, vitals: vitals)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('a mano: duración mm:ss, pulso y kcal salen del formulario', (tester) async {
    final results = await open(tester);
    expect(find.text('Datos del reloj'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Duración (mm:ss o h:mm:ss)'), '31:16');
    await tester.enterText(find.widgetWithText(TextField, 'Pulso medio (lpm)'), '100');
    await tester.enterText(find.widgetWithText(TextField, 'Pulso máximo (lpm)'), '124');
    await tester.enterText(find.widgetWithText(TextField, 'kcal del reloj (informativas)'), '248');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final r = results.single!;
    expect((r.durationSec, r.avgHr, r.maxHr, r.kcal), (31 * 60 + 16, 100, 124, 248));
    expect(r.systolic, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lo leído de la captura llega prellenado para confirmar', (tester) async {
    final results = await open(tester,
        initial: parseWatchText('Caminar 12:56 p. m. 10:19 134 / 154 lpm 49 kcal'));
    expect(find.widgetWithText(TextField, 'Caminar'), findsOneWidget);
    expect(find.widgetWithText(TextField, '10:19'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect((results.single!.avgHr, results.single!.maxHr), (134, 154));
  });

  testWidgets('un pulso imposible no sale del formulario', (tester) async {
    final results = await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Pulso medio (lpm)'), '150');
    await tester.enterText(find.widgetWithText(TextField, 'Pulso máximo (lpm)'), '120');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('El pulso máximo es menor que el medio'), findsOneWidget);
    expect(results, isEmpty);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });

  testWidgets('presión: rotulada como estimación y exige los dos números', (tester) async {
    final results = await open(tester, vitals: true);
    expect(find.text('Presión y SpO₂: estimación del reloj, no es una medida clínica.'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Pulso medio (lpm)'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Presión alta (mmHg)'), '122');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('La presión lleva los dos números (alta / baja)'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Presión baja (mmHg)'), '76');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect((results.single!.systolic, results.single!.diastolic), (122, 76));
  });
}
