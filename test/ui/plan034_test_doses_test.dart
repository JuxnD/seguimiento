import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/features/body/test_results_screen.dart';

void main() {
  testWidgets('public dose never uses unknown legacy conditions',
      (tester) async {
    await withClock(Clock.fixed(DateTime(2030, 2, 6)), () async {
      // Control positivo previo: demuestra que el finder apunta a esta dosis.
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TestDoses(results: [
        TestResult(
            round: 1,
            item: 'pullup',
            value: 5,
            date: DateTime(2030, 2, 4),
            attemptId: 17,
            conditions: '{"grip":"prona","variant":"barra"}')
      ]))));
      expect(
          find.textContaining('Dominadas pronas estrictas:'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TestDoses(results: [
        TestResult(
            round: 1, item: 'pullup', value: 5, date: DateTime(2030, 2, 4))
      ]))));
      expect(find.textContaining('Dominadas pronas estrictas:'), findsNothing);
    });
  });
  testWidgets('public dose labels the single known attempt and reverse maximum',
      (tester) async {
    await withClock(Clock.fixed(DateTime(2030, 2, 6)), () async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TestDoses(results: [
        TestResult(
            round: 1,
            item: 'pullup',
            value: 5,
            date: DateTime(2030, 2, 4),
            attemptId: 17,
            protocolId: 'v32_13',
            conditions: '{"grip":"prona","variant":"barra"}'),
        TestResult(
            round: 1,
            item: 'reverse_plank_forearm',
            value: 80,
            date: DateTime(2030, 2, 4),
            attemptId: 17,
            protocolId: 'v32_13',
            conditions: '{"support":"suelo","variant":"antebrazos"}')
      ]))));
      expect(
          find.textContaining(
              'Dominadas pronas estrictas: Tope del rango: 3–4 reps'),
          findsOneWidget);
      expect(find.textContaining('intento17, 2030-02-04, v32_13'),
          findsNWidgets(2));
      expect(find.textContaining('Series de 40–48 s'), findsOneWidget);
    });
  });
}
