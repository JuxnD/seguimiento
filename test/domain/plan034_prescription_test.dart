import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/ladder_prescription_proof.dart';
import 'package:seguimiento/domain/series_side_proof.dart';

void main() {
  test('neutral maintenance does not advance and partial target breaks', () {
    final since = DateTime(2030, 2, 4), today = DateTime(2030, 2, 28);
    final rows = [
      LadderSession(date: DateTime(2030, 2, 18), sets: {
        'Plancha inversa sobre antebrazos': [45, 45, 45]
      }),
      LadderSession(
          date: DateTime(2030, 2, 21),
          sets: {
            'Plancha inversa sobre antebrazos': [45, 45]
          },
          maintenance: true),
      LadderSession(date: DateTime(2030, 2, 25), sets: {
        'Plancha inversa sobre antebrazos': [45, 45, 45]
      }),
    ];
    expect(
        ladderAdvice(reversePlankLadder, 1, since, rows, today).cleanInARow, 2);
    expect(
        ladderAdvice(
                reversePlankLadder,
                1,
                since,
                [
                  ...rows,
                  LadderSession(date: today, sets: {
                    'Plancha inversa sobre antebrazos': [45, 45]
                  })
                ],
                today)
            .cleanInARow,
        0);
    expect(
        ladderAdvice(reversePlankLadder, 1, since, [rows[1]], today).canStepUp,
        isFalse);
  });
  test(
      'versioned prescription is bound to epoch; corrupt or unknown proof stays unknown',
      () {
    final raw = LadderPrescriptionProof.maintenance(
        identity: '1:4', sets: 2, minimum: 20, perSide: false);
    expect(LadderPrescriptionProof.decode(raw, '1:4'),
        (sets: 2, minimum: 20, perSide: false));
    expect(LadderPrescriptionProof.decode(raw, '1:5'), isNull);
    for (final invalid in [null, '{}', '[]', '{"version":2}', 'not-json']) {
      expect(LadderPrescriptionProof.decode(invalid, '1:4'), isNull);
      expect(SeriesSideProof.decode(invalid), isNull);
    }
    expect(SeriesSideProof.decode(SeriesSideProof.encode(['I', 'D', null])),
        ['I', 'D', null]);
  });
  test('two repeated same-side performances cannot prove bilateral criterion',
      () {
    final since = DateTime(2030, 2, 4), today = DateTime(2030, 2, 28);
    List<LadderSession> rows(List<String?> sides) => [
          for (final day in [18, 25])
            LadderSession(date: DateTime(2030, 2, day), sets: {
              'Plancha inversa con patada': [10, 10, 10, 10]
            }, sides: {
              'Plancha inversa con patada': sides
            })
        ];
    expect(
        ladderAdvice(
                reversePlankLadder, 4, since, rows(['I', 'I', 'I', 'I']), today)
            .canStepUp,
        isFalse);
    expect(
        ladderAdvice(reversePlankLadder, 4, since,
                rows([null, null, null, null]), today)
            .canStepUp,
        isFalse);
    expect(
        ladderAdvice(
                reversePlankLadder, 4, since, rows(['I', 'D', 'I', 'D']), today)
            .canStepUp,
        isTrue);
  });
}
