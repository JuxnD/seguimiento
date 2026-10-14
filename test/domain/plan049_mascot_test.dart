import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/mascot.dart';

/// Plan 049: Rayito crece con la racha de constancia (8 fases elegidas con el
/// owner el 14 oct) y su cara dice cómo va el día.
void main() {
  test('cada borde de fase cae en el día exacto', () {
    const edges = {
      0: MascotPhase.dormido,
      1: MascotPhase.despierto,
      2: MascotPhase.despierto,
      3: MascotPhase.cargado,
      6: MascotPhase.cargado,
      7: MascotPhase.energizado,
      13: MascotPhase.energizado,
      14: MascotPhase.tormenta,
      20: MascotPhase.tormenta,
      21: MascotPhase.super_,
      29: MascotPhase.super_,
      30: MascotPhase.prime,
      59: MascotPhase.prime,
      60: MascotPhase.leyenda,
      400: MascotPhase.leyenda,
    };
    for (final e in edges.entries) {
      expect(mascotPhase(e.key), e.value, reason: '${e.key} días');
    }
  });

  test('días para la siguiente fase; la última no tiene siguiente', () {
    expect(daysToNextPhase(0), 1);
    expect(daysToNextPhase(5), 2);
    expect(daysToNextPhase(29), 1);
    expect(daysToNextPhase(59), 1);
    expect(daysToNextPhase(60), isNull);
    expect(MascotPhase.leyenda.next, isNull);
  });

  test('las fases van en orden de crecimiento, sin huecos ni repetidos', () {
    final from = [for (final p in MascotPhase.values) p.fromDays];
    expect(from.first, 0);
    for (var i = 1; i < from.length; i++) {
      expect(from[i], greaterThan(from[i - 1]));
    }
  });

  test(
      'cara del día: registrar manda; el descanso de 032 no presiona; sin racha duerme',
      () {
    expect(mascotMood(streak: 5, activeToday: true, restAdvised: true),
        MascotMood.contento);
    expect(mascotMood(streak: 5, activeToday: false, restAdvised: true),
        MascotMood.sereno);
    expect(mascotMood(streak: 0, activeToday: false, restAdvised: true),
        MascotMood.sereno);
    expect(mascotMood(streak: 5, activeToday: false, restAdvised: false),
        MascotMood.atento);
    expect(mascotMood(streak: 0, activeToday: false, restAdvised: false),
        MascotMood.dormido);
  });
}
