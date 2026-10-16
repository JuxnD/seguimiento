import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/ui/progress_ring.dart';
import 'package:seguimiento/ui/widgets.dart';

/// Plan 057: correcciones P1 de la auditoría 053 que viven en widgets
/// compartidos.
void main() {
  testWidgets('«atrás» en un formulario tocado pregunta antes de perderlo',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const UnsavedChangesGuard(
                        child: Scaffold(body: Text('Formulario'))))),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    // Sin tocar nada, sale directo.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Formulario'), findsNothing);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Formulario'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('¿Salir sin guardar?'), findsOneWidget);
    await tester.tap(find.text('Seguir'));
    await tester.pumpAndSettle();
    expect(find.text('Formulario'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salir sin guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Formulario'), findsNothing);
  });

  testWidgets('anillo chico: la meta va debajo con letra que crece',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Center(
            child: ProgressRing(
                progress: .5,
                value: '1.050',
                sublabel: 'de 2.100–2.200',
                label: 'kcal',
                size: 80),
          ),
        ),
      ),
    ));
    final meta = find.text('de 2.100–2.200');
    expect(meta, findsOneWidget);
    expect(find.ancestor(of: meta, matching: find.byType(FittedBox)),
        findsNothing,
        reason: 'fuera del FittedBox no se encoge');
    expect(
        find.bySemanticsLabel('kcal, 1.050, de 2.100–2.200'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
