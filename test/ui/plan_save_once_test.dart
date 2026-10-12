import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/features/plan/plan_edit_screen.dart';

import '../support/sqlite_host.dart';

// Retiene sólo la frontera de escritura; el guardado final es SQLite real.
class _PendingPlan extends PlanRepository {
  _PendingPlan(super.db, super.exercises);
  Completer<void> gate = Completer<void>();
  int calls = 0;
  bool fail = false;
  final completions = <Future<int>>[];
  @override
  Future<int> saveAsNewVersion(PlanDraft draft) {
    calls++;
    final result = _write(draft);
    completions.add(result);
    return result;
  }

  Future<int> _write(PlanDraft draft) async {
    await gate.future;
    if (fail) throw StateError('fallo ficticio');
    return super.saveAsNewVersion(draft);
  }
}

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late _PendingPlan repo;
  setUp(() {
    db = openInMemoryDatabase();
    repo = _PendingPlan(db, ExerciseRepository(db));
  });
  tearDown(() => db.close());

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => Navigator.of(context)
                                  .push(MaterialPageRoute<void>(
                                builder: (_) => PlanEditScreen(
                                    draft: PlanDraft.empty(
                                        DateTime(2026, 10, 12))),
                              )),
                          child: const Text('Abrir')),
                    )))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('doble toque pendiente crea sólo una versión SQLite',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);
    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar versión'));
      await tester.tap(find.text('Guardar versión'));
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);
      repo.gate.complete();
      await Future.wait(repo.completions);
    });
    await tester.pumpAndSettle();
    final rows = await tester.runAsync(() => db.select(db.planVersions).get());
    expect(rows, hasLength(1));
    expect(repo.calls, 1);
    expect(find.text('Abrir'), findsOneWidget);
  });

  testWidgets('error conserva editor y permite reintentar', (tester) async {
    await mount(tester);
    repo.fail = true;
    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar versión'));
      repo.gate.complete();
      try {
        await repo.completions.last;
      } on StateError {/* UI informa el error. */}
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nueva versión del plan'), findsOneWidget);
    expect(find.textContaining('No se pudo guardar'), findsOneWidget);
    repo.fail = false;
    await tester.runAsync(() async {
      repo.gate = Completer<void>();
      await tester.tap(find.text('Guardar versión'));
      repo.gate.complete();
      await repo.completions.last;
    });
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => db.select(db.planVersions).get()),
        hasLength(1));
    expect(repo.calls, 2);
  });
}
