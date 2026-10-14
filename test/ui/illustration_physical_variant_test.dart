import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';

Map<String, Object?> fixture() {
  final data = jsonDecode(File(Figure3DCatalog.asset).readAsStringSync()) as Map<String, Object?>;
  final base = (data['figures'] as List).cast<Map<String, Object?>>().firstWhere((f) => f['name'] == 'Dominadas');
  final alternate = jsonDecode(jsonEncode(base)) as Map<String, Object?>;
  ((alternate['frames'] as List).first as Map<String, Object?>)['caption'] = 'Postura alternativa de prueba';
  data['physicalVariants'] = [
    {'exercise': 'Dominadas', 'key': 'base', 'useBase': true},
    {'exercise': 'Dominadas', 'key': 'alternate', 'figure': alternate},
  ];
  return data;
}

void main() {
  test('physical variants resolve by exercise and explicit key without substituting a base pose', () {
    final catalog = Figure3DCatalog.fromJsonString(jsonEncode(fixture()));
    final base = catalog.forExercise('Dominadas')!;
    expect(catalog.forExercise('DOMINADAS', physicalVariantKey: 'base'), same(base));
    expect(catalog.forExercise('Dominadas', physicalVariantKey: 'alternate')!.frames.first.caption,
        'Postura alternativa de prueba');
    expect(catalog.forExercise('Dominadas', physicalVariantKey: 'unknown'), isNull);
    expect(catalog.forExercise('Fondos en barra', physicalVariantKey: 'alternate'), isNull);
    expect(catalog.forExercise('Dominadas'), same(base));
    final malformed = fixture();
    final malformedVariants = (malformed['physicalVariants'] as List).cast<Map<String, Object?>>();
    (malformedVariants[1]['figure'] as Map<String, Object?>)['name'] = 'Otro ejercicio';
    expect(() => Figure3DCatalog.fromJsonString(jsonEncode(malformed)), throwsFormatException);
    final duplicate = fixture();
    final duplicateVariants = duplicate['physicalVariants'] as List;
    duplicateVariants.add(duplicateVariants.first);
    expect(() => Figure3DCatalog.fromJsonString(jsonEncode(duplicate)), throwsFormatException);
  });

  testWidgets('the shared view shows the selected physical pose or explicit absence', (tester) async {
    final catalog = Figure3DCatalog.fromJsonString(jsonEncode(fixture()));
    Future<void> show(String? key) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [figure3dProvider.overrideWith((ref) async => catalog)],
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
          child: ExerciseFigureView(exercise: 'Dominadas', physicalVariantKey: key),
        ))),
      ));
      await tester.pumpAndSettle();
    }

    await show('unknown');
    expect(find.text('Esta variante todavía no tiene una ilustración. Puedes añadir una foto de referencia.'),
        findsOneWidget);
    expect(find.byType(Figure3DMoments), findsNothing);
    await show('alternate');
    expect(tester.widget<Figure3DMoments>(find.byType(Figure3DMoments)).figure.frames.first.caption,
        'Postura alternativa de prueba');
    await show(null);
    expect(tester.widget<Figure3DMoments>(find.byType(Figure3DMoments)).figure, same(catalog.forExercise('Dominadas')));
    expect(tester.takeException(), isNull);
  });
}
