import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/warmup.dart';
import 'package:seguimiento/features/training/pre_attempt_card.dart';

/// Día de test (§16.23): calentamiento y checklist siempre a la vista.
void main() {
  testWidgets('la tarjeta muestra el calentamiento y los 4 puntos del checklist, y se marcan', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PreAttemptCard(torso: true)))));

    expect(find.text('Antes del intento'), findsOneWidget);
    for (final check in preAttemptChecklist) {
      expect(find.text(check), findsOneWidget);
    }
    expect(find.text('Colgado pasivo · 20 s'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(testWarmup(torso: true).length + 4));

    await tester.tap(find.text('Agua a mano'));
    await tester.pump();
    final tile = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Agua a mano'));
    expect(tile.value, isTrue);
  });
}
