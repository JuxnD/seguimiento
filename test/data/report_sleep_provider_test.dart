import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/sleep_repository.dart';
import 'package:seguimiento/domain/dates.dart';

import '../support/sqlite_host.dart';

typedef _SleepSnapshot = ({
  Map<String, double> current,
  Map<String, double> previous,
});

void main() {
  setUpAll(useHostSqlite);

  test('el informe se refresca al anotar o quitar sueño actual y previo',
      () async {
    final db = openInMemoryDatabase();
    final sleep = SleepRepository(db);
    final container =
        ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    const range = ('2026-10-05', '2026-10-11');
    const currentNight = '2026-10-06';
    const previousNight = '2026-10-01';
    Map<String, double> keys(Map<DateTime, double> values) =>
        values.map((date, hours) => MapEntry(dayKey(date), hours));
    bool same(Map<String, double> left, Map<String, double> right) =>
        left.length == right.length &&
        left.entries.every((entry) => right[entry.key] == entry.value);

    Completer<_SleepSnapshot>? expected;
    var expectedSnapshot = (
      current: const <String, double>{},
      previous: const <String, double>{},
    );
    final subscription =
        container.listen(reportInputProvider(range), (_, next) {
      final input = next.valueOrNull;
      final current = input == null ? null : keys(input.sleep);
      final previous =
          input?.previous == null ? null : keys(input!.previous!.sleep);
      if (current != null &&
          previous != null &&
          same(current, expectedSnapshot.current) &&
          same(previous, expectedSnapshot.previous) &&
          expected != null) {
        final pending = expected!;
        expected = null;
        pending.complete((current: current, previous: previous));
      }
    }, fireImmediately: true);
    addTearDown(subscription.close);

    Future<_SleepSnapshot> expectSleep(
        Map<String, double> current, Map<String, double> previous) async {
      expectedSnapshot = (current: current, previous: previous);
      expected = Completer<_SleepSnapshot>();
      return expected!.future.timeout(const Duration(seconds: 5));
    }

    final initial = expectSleep(const {}, const {});
    await container.read(reportInputProvider(range).future);
    await initial;
    final currentAdded = expectSleep(const {currentNight: 7.5}, const {});
    await sleep.set(DateTime(2026, 10, 6), 7.5);
    expect((await currentAdded).current, {currentNight: 7.5});

    final previousAdded =
        expectSleep(const {currentNight: 7.5}, const {previousNight: 6.5});
    await sleep.set(DateTime(2026, 10, 1), 6.5);
    expect((await previousAdded).previous, {previousNight: 6.5});

    final currentRemoved = expectSleep(const {}, const {previousNight: 6.5});
    await sleep.remove(DateTime(2026, 10, 6));
    expect((await currentRemoved).previous, {previousNight: 6.5});

    final previousRemoved = expectSleep(const {}, const {});
    await sleep.remove(DateTime(2026, 10, 1));
    expect((await previousRemoved).previous, isEmpty);
  });
}
