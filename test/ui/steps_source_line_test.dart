import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/domain/steps.dart';
import 'package:seguimiento/features/home/steps_source_line.dart';

/// §16.14: la línea de Hoy dice quién escribió los pasos y a qué hora, y pide
/// abrir la app del reloj si lleva más de 6 h sin escribir.
void main() {
  final now = DateTime(2026, 10, 3, 16);
  final innova = StepsOrigin(at: DateTime(2026, 10, 3, 15, 6), package: 'com.moyoung.innov', label: 'INNOVA S-WATCH');

  Future<void> pump(WidgetTester tester, {required bool enabled, StepsOrigin? origin}) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            stepsSyncInfoProvider.overrideWithValue((enabled: enabled, lastSync: now, origin: origin)),
          ],
          child: MaterialApp(home: Scaffold(body: StepsSourceLine(now: now))),
        ),
      );

  testWidgets('al día: solo la app y la hora', (tester) async {
    await pump(tester, enabled: true, origin: innova);
    expect(find.text('INNOVA S-WATCH · 3:06 p. m.'), findsOneWidget);
    expect(find.text('Abre la app del reloj para sincronizar'), findsNothing);
  });

  testWidgets('más de 6 h o sin registros: pide abrir la app del reloj', (tester) async {
    final old = StepsOrigin(at: DateTime(2026, 10, 3, 8), package: innova.package, label: innova.label);
    await pump(tester, enabled: true, origin: old);
    expect(find.text('INNOVA S-WATCH · 8:00 a. m.'), findsOneWidget);
    expect(find.text('Abre la app del reloj para sincronizar'), findsOneWidget);

    await pump(tester, enabled: true);
    expect(find.text('Abre la app del reloj para sincronizar'), findsOneWidget);
  });

  testWidgets('sin Health Connect conectado no dice nada', (tester) async {
    await pump(tester, enabled: false);
    expect(find.byType(Text), findsNothing);
  });
}
