import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/coalesce.dart';

void main() {
  test('nunca corre dos veces a la vez', () async {
    var running = 0, maxRunning = 0, runs = 0;
    final gate = Completer<void>();
    final run = coalesce(() async {
      running++;
      maxRunning = running > maxRunning ? running : maxRunning;
      runs++;
      if (runs == 1) await gate.future;
      running--;
    });

    final first = run();
    unawaited(run());
    unawaited(run());
    gate.complete();
    await first;

    expect(maxRunning, 1);
    // La primera y una sola repetición por los pedidos que llegaron mientras corría.
    expect(runs, 2);
  });

  test('un pedido durante la ejecución no se pierde', () async {
    final seen = <int>[];
    var value = 0;
    final gate = Completer<void>();
    final run = coalesce(() async {
      final v = value;
      if (seen.isEmpty) await gate.future;
      seen.add(v);
    });

    final first = run();
    value = 1; // Llega un cambio mientras la primera corrida espera.
    unawaited(run());
    gate.complete();
    await first;

    expect(seen.last, 1, reason: 'la última corrida debe ver el cambio');
  });

  test('tras terminar, un pedido nuevo vuelve a correr', () async {
    var runs = 0;
    final run = coalesce(() async => runs++);
    await run();
    await run();
    expect(runs, 2);
  });

  test('si la tarea falla, el siguiente pedido corre igual', () async {
    var runs = 0;
    final run = coalesce(() async {
      runs++;
      if (runs == 1) throw StateError('falla');
    });
    await expectLater(run(), throwsStateError);
    await run();
    expect(runs, 2);
  });
}
