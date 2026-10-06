import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/recovery.dart';

/// Recuperación y carga (§16.15, §19.6–19.8).
void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);

  group('pesaje', () {
    test('los pesajes viejos toman el momento de "en ayunas"', () {
      expect(weighMomentOf(null, fasted: true), WeighMoment.ayunas);
      expect(weighMomentOf(null, fasted: false), WeighMoment.otro);
      expect(weighMomentOf('antesDormir', fasted: false), WeighMoment.antesDormir);
      expect(WeighMoment.otro.onePerDay, isFalse, reason: 'después de desayunar y antes de cenar caben el mismo día');
    });
  });

  group('molestias', () {
    test('no baja en 3 días o sube: avisa', () {
      final today = d(10, 8);
      expect(
        persistentSoreness({
          d(10, 6): {'Isquios': 6, 'Rodilla': 5},
          d(10, 7): {'Isquios': 6, 'Rodilla': 3},
          d(10, 8): {'Isquios': 6, 'Rodilla': 2},
        }, today),
        ['Isquios'],
        reason: 'la rodilla baja; los isquios no',
      );
      expect(persistentSoreness({d(10, 7): {'Gemelo': 2}, d(10, 8): {'Gemelo': 4}}, today), ['Gemelo'],
          reason: 'sube de un día a otro');
      expect(persistentSoreness({d(10, 8): {'Gemelo': 0}}, today), isEmpty);
    });
  });

  group('pulso en reposo', () {
    test('3 días seguidos 5 lpm por encima de la media: recuperación baja', () {
      final today = d(10, 20);
      final byDay = {
        for (var i = 3; i < 10; i++) d(10, 20 - i): 58,
        d(10, 18): 64,
        d(10, 19): 65,
        d(10, 20): 66,
      };
      expect(restingHrWarning(byDay, today), contains('considera la versión ligera'));
      expect(restingHrWarning({...byDay, d(10, 19): 59}, today), isNull, reason: 'un día normal corta la racha');
      expect(restingHrAverage({d(10, 20): 60, d(10, 19): 62}, today), 61);
    });
  });

  group('carga', () {
    test('circuito y fútbol intenso el mismo día: dos sesiones, otra sesión pide confirmar', () {
      final today = d(10, 5);
      final r = loadReading([
        LoadItem(date: today, minutes: 20, effort: 7),
        LoadItem(date: today, minutes: 90, effort: 8, isFootball: true),
        LoadItem(date: d(10, 4), minutes: 90, effort: 8, isFootball: true),
        LoadItem(date: d(10, 3), minutes: 90, effort: 7, isFootball: true),
      ], today);
      expect((r.todayCount, r.todayLoad, r.intenseStreak), (2, 860, 3));
      expect(r.warnAnotherSession, isTrue);
      expect(r.reason, contains('dos veces hoy'));
    });

    test('sin nada hoy, la racha cuenta desde ayer', () {
      final r = loadReading([
        LoadItem(date: d(10, 4), minutes: 60, effort: 8),
        LoadItem(date: d(10, 3), minutes: 60, effort: 9),
        LoadItem(date: d(10, 2), minutes: 60, effort: 5),
      ], d(10, 5));
      expect((r.intenseStreak, r.warnAnotherSession), (2, false));
    });

    test('plan B: día con pierna y 3 días intensos o molestia en la pierna', () {
      const tired = LoadReading(todayLoad: 0, todayCount: 0, intenseStreak: 3);
      const fresh = LoadReading(todayLoad: 0, todayCount: 0, intenseStreak: 0);
      final today = d(10, 6);
      expect(suggestPlanB(dayHasLegs: true, load: tired, soreness: const {}, today: today), isTrue);
      expect(suggestPlanB(dayHasLegs: false, load: tired, soreness: const {}, today: today), isFalse);
      expect(
        suggestPlanB(dayHasLegs: true, load: fresh, soreness: {d(10, 5): {'Cuádriceps': 4}}, today: today),
        isTrue,
        reason: 'agujetas de ayer en la pierna',
      );
      expect(suggestPlanB(dayHasLegs: true, load: fresh, soreness: {d(10, 5): {'Hombro': 6}}, today: today), isFalse);
    });
  });

  group('planche (§19.7)', () {
    test('martes con pseudo-planche; jueves sin; lunes nada', () {
      final tue = plancheBlock(weekday: DateTime.tuesday, deload: false, tuckReady: false).map((e) => e.name);
      expect(tue, ['Muñecas (planche)', 'Inclinación de planche', 'Flexión pseudo-planche']);
      final thu = plancheBlock(weekday: DateTime.thursday, deload: false, tuckReady: true).map((e) => e.name);
      expect(thu, ['Muñecas (planche)', 'Inclinación de planche', 'Tuck planche']);
      expect(plancheBlock(weekday: DateTime.monday, deload: false, tuckReady: true), isEmpty);
    });

    test('en descarga, solo inclinaciones', () {
      expect(plancheBlock(weekday: DateTime.tuesday, deload: true, tuckReady: true).map((e) => e.name),
          ['Inclinación de planche']);
    });
  });

  test('hoja de habilidades: ventanas desde oct 2026', () {
    final lsit = skillRoadmap.firstWhere((s) => s.id == 'l_sit');
    expect(skillWindow(lsit), (DateTime(2026, 10), DateTime(2027, 1)));
    final planche = skillRoadmap.firstWhere((s) => s.id == 'full_planche');
    expect(planche.window, '2–5 años');
  });
}
