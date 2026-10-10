import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';
import 'package:seguimiento/ui/theme.dart';
import '../support/test_fonts.dart';

void main() {
  final cat = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
  for (final scale in [1.6, 2.0]) {
    testWidgets('CTA completa y accesible en360px texto$scale', (tester) async {
      await loadTestFonts(tester);
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final theme = buildGymTheme();
      try {
        for (final name in ['Círculos de hombros', 'Balanceos de pierna']) {
          await tester.pumpWidget(MaterialApp(
              theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Roboto')),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
              home: Scaffold(
                  body: ListView(children: [
                Padding(
                    padding: const EdgeInsets.all(20),
                    child: Figure3DMoments(key: ValueKey('$name/$scale'), figure: cat.forExercise(name)!))
              ]))));
          await tester.pump();
          void complete(String label) {
            final finder = find.text(label);
            expect(finder, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(finder);
            final end = label.length;
            expect(paragraph.getBoxesForSelection(TextSelection(baseOffset: end - 1, extentOffset: end)), isNotEmpty,
                reason: 'última letra debe pintarse: $label, $name ×$scale');
            expect(
                tester
                    .getSemantics(find
                        .ancestor(of: finder, matching: find.byWidgetPredicate((widget) => widget is TextButton))
                        .first)
                    .label,
                contains(label));
          }

          complete('Ver movimiento');
          await tester.ensureVisible(find.text('Ver movimiento'));
          await tester.tap(find.text('Ver movimiento'));
          await tester.pump();
          complete('Ver momentos');
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Ver momentos'));
          await tester.pump();
        }
      } finally {
        semantics.dispose();
      }
    });
  }
}
