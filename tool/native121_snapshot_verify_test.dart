// QA: current parser/script versus frozen sequence emitted by source1.20.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/domain/session_script.dart';
import 'package:seguimiento/data/guided_plan_snapshot.dart';
import 'package:seguimiento/features/training/guided_session_screen.dart';

void main() {
  test('native release snapshot preserves all legacy script steps and doses', () async {
    final manifest = jsonDecode(await File(Platform.environment['NATIVE121_MANIFEST']!).readAsString()) as Map;
    final snapshot =
        ActiveSession.fromJson(jsonDecode(await File(Platform.environment['NATIVE121_SNAPSHOT']!).readAsString()))
            as GuidedSnapshot;
    expect(snapshot.index, manifest['index']);
    final script = buildScript(scriptDayFrom(thawGuidedDay(snapshot.effectiveDay!)),
        coreVariant: snapshot.coreVariant, rounds: snapshot.roundsOverride);
    final steps = [
      for (final s in script)
        switch (s) {
          final WorkStep w => {
              'kind': 'work',
              'exercise': w.exercise,
              'targetLabel': w.targetLabel,
              'targetReps': w.targetReps,
              'holdSec': w.holdSec,
              'holdSecMax': w.holdSecMax,
              'position': w.position,
              'total': w.total,
              'isRound': w.isRound,
              'blockName': w.blockName,
              'grip': w.grip,
              'side': w.side
            },
          final RestStep r => {'kind': 'rest', 'seconds': r.seconds, 'maxSec': r.maxSec, 'nextLabel': r.nextLabel}
        }
    ];
    expect(steps, manifest['steps']);
    expect(snapshot.done.map((d) => d.toJson()).toList(), (manifest['legacySnapshot'] as Map)['done']);
  });
}
