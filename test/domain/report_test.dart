import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/report/alerts.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/domain/report/report_input.dart';
import 'package:seguimiento/domain/report/report_stats.dart';

/// Semana 4 (mié 16 sep – mar 22 sep 2026) con un caso realista.
ReportInput weekFour({List<MealEntry>? meals, List<MeasurementEntry>? measurements, String? notes}) {
  final start = DateTime(2026, 8, 26);
  final w = weekRange(start, 4);
  DateTime d(int day) => DateTime(2026, 9, day);

  // Plan v1: lun-vie circuito salvo mar/jue fútbol. v2 desde el 20 sep cambia vie a bloques.
  final v1 = PlanVersionInfo(number: 1, validFrom: start, dayTypes: {
    1: DayType.circuito,
    2: DayType.futbol,
    3: DayType.circuito,
    4: DayType.futbol,
    5: DayType.circuito,
  });
  final v2 = PlanVersionInfo(number: 2, validFrom: d(20), dayTypes: {
    1: DayType.circuito,
    2: DayType.futbol,
    3: DayType.circuito,
    4: DayType.futbol,
    5: DayType.bloques,
  });

  SetEntry set(String ex, int i, int reps, {bool split = false, String? detail, bool fail = false}) =>
      SetEntry(exercise: ex, setIndex: i, reps: reps, split: split, splitDetail: detail, toFailure: fail);

  return ReportInput(
    programStart: start,
    rangeStart: w.start,
    rangeEnd: w.end,
    today: d(22),
    planVersions: [v2, v1],
    previousRoundsRecord: 7,
    sessions: [
      SessionEntry(
        date: d(18),
        startTime: '15:10',
        type: SessionType.circuito,
        totalSec: 1200,
        warmupSec: 540,
        cooldownSec: 180,
        roundsDone: 8,
        rpe: 8,
        limitingExercise: 'Flexiones',
        context: 'Oficina | fútbol intenso ayer',
        notes: 'La 6ª con margen',
        lapsSec: [150, 160, 170],
        sets: [
          set('Flexiones', 1, 15),
          set('Flexiones', 2, 15),
          set('Flexiones', 3, 15, split: true, detail: '12+3', fail: true),
          set('Sentadillas', 1, 20),
        ],
      ),
      SessionEntry(
        date: d(16),
        startTime: '07:00',
        type: SessionType.circuito,
        totalSec: 1100,
        warmupSec: 300,
        cooldownSec: 120,
        roundsDone: 6,
        roundsEstimated: true,
        sets: [set('Flexiones', 1, 10, split: true, detail: '6+4')],
      ),
      SessionEntry(
        date: d(21),
        startTime: '18:00',
        type: SessionType.circuito,
        totalSec: 1200,
        warmupSec: 400,
        cooldownSec: 180,
        roundsDone: 7,
        sets: [set('Flexiones', 1, 12, split: true, detail: '8+4')],
      ),
    ],
    football: [
      FootballEntry(date: d(17), format: 5, minutes: 60, steps: 7200, intensity: 8, fatigueAfter: 6),
    ],
    meals: meals ??
        [
          MealEntry(date: d(16), slot: MealSlot.desayuno, time: '07:30', items: [
            const MealItemEntry(label: 'Huevo', quantityLabel: '×3', macros: Macros(kcal: 216, protein: 19)),
          ]),
          MealEntry(date: d(16), slot: MealSlot.almuerzo, items: [
            const MealItemEntry(label: 'Bandeja', macros: Macros(kcal: 1500, protein: 50)),
          ]),
          MealEntry(date: d(17), slot: MealSlot.cena, items: [
            const MealItemEntry(label: 'Atún', quantityLabel: '×1', macros: Macros(kcal: 1800, protein: 70)),
          ]),
          MealEntry(date: d(18), slot: MealSlot.almuerzo, items: [
            const MealItemEntry(label: 'Rappi', macros: Macros(kcal: 2600, protein: 150)),
          ]),
        ],
    weightsInRange: [WeightEntry(date: d(18), kg: 71.4), WeightEntry(date: d(20), kg: 71.0)],
    baselineWeight: WeightEntry(date: start, kg: 72.3),
    measurementsInRange: measurements ?? const [],
    baselineMeasurements: {
      MeasureSite.abdomen: MeasurementEntry(date: start, site: MeasureSite.abdomen, valueCm: 86),
    },
    measurementDatesBefore: [start],
    notes: notes,
  );
}

void main() {
  group('estadísticas', () {
    test('sesiones esperadas usan la versión vigente de cada día', () {
      final s = ReportStats(weekFour());
      // mié16 C, jue17 F, vie18 C, sáb, dom, lun21 C, mar22 F (v2 igual en esos días)
      expect(s.expectedTraining, 3);
      expect(s.expectedFootball, 2);
      expect(s.plansInRange.map((p) => p.number), [1, 2]);
    });

    test('promedios solo sobre días registrados', () {
      final s = ReportStats(weekFour());
      expect(s.loggedDays.length, 3);
      expect(s.avgKcal, closeTo((1716 + 1800 + 2600) / 3, 1e-9));
      expect(s.unloggedDays.map((d) => d.day), [19, 20, 21, 22]);
      expect(s.maxRoundsInRange, 8);
    });
  });

  group('alertas', () {
    test('detecta las reglas del plan', () {
      final alerts = buildAlerts(ReportStats(weekFour()));
      expect(alerts, contains('2 días seguidos bajo 2.000 kcal (mié 16, jue 17)'));
      expect(alerts, contains('Flexiones partidas en 3 sesiones'));
      expect(alerts, contains('Calentamiento < 6 min en 1 sesión'));
      expect(alerts, contains('Rondas estimadas por tiempo (no contadas) en 1 sesión'));
      expect(alerts.first, startsWith('Sin registro de comidas: sáb 19, dom 20, lun 21, mar 22'));
    });

    test('medición antes de tiempo', () {
      final input = weekFour(measurements: [
        MeasurementEntry(date: DateTime(2026, 9, 16), site: MeasureSite.abdomen, valueCm: 84, fasted: false),
        MeasurementEntry(date: DateTime(2026, 9, 20), site: MeasureSite.abdomen, valueCm: 83.5),
      ]);
      final alerts = buildAlerts(ReportStats(input));
      // 26 ago → 16 sep = 21 días: permitido. 16 → 20 sep = 4 días: alerta.
      expect(alerts.where((a) => a.startsWith('Medición')),
          ['Medición del 20 sep a solo 4 días de la anterior (mínimo 21)']);
      expect(alerts, contains('Medidas tomadas sin ayunas: 16 sep'));
    });

    test('sin alerta de intervalo cuando se respeta el mínimo', () {
      final input = weekFour(measurements: [
        MeasurementEntry(date: DateTime(2026, 9, 18), site: MeasureSite.abdomen, valueCm: 84),
      ]);
      expect(buildAlerts(ReportStats(input)).where((a) => a.startsWith('Medición')), isEmpty);
    });
  });

  group('sesiones fuera de plan e incompletas', () {
    ReportInput withSession(SessionEntry session) {
      final base = weekFour();
      return ReportInput(
        programStart: base.programStart,
        rangeStart: base.rangeStart,
        rangeEnd: base.rangeEnd,
        today: base.today,
        planVersions: base.planVersions,
        sessions: [session],
      );
    }

    test('avisa del tipo fuera de plan y de la sesión incompleta', () {
      final alerts = buildAlerts(ReportStats(withSession(SessionEntry(
        date: DateTime(2026, 9, 18),
        type: SessionType.bloques,
        totalSec: 1200,
        warmupSec: 400,
        cooldownSec: 120,
        roundsDone: 7,
        plannedRounds: 8,
        outOfPlan: true,
        incomplete: true,
      ))));
      expect(alerts, contains('Fuera de plan: Bloques el 18 sep'));
      expect(alerts, contains('Sesiones cerradas antes de completar el plan: 18 sep'));
    });

    test('avisa del enfriamiento corto', () {
      final alerts = buildAlerts(ReportStats(withSession(SessionEntry(
        date: DateTime(2026, 9, 18),
        type: SessionType.circuito,
        totalSec: 1200,
        warmupSec: 400,
        cooldownSec: 30,
      ))));
      expect(alerts, contains('Enfriamiento < 1 min en 1 sesión'));
    });

    test('la tabla muestra rondas hechas sobre planificadas', () {
      final md = buildReport(withSession(SessionEntry(
        date: DateTime(2026, 9, 18),
        startTime: '15:10',
        type: SessionType.circuito,
        totalSec: 1200,
        warmupSec: 540,
        cooldownSec: 180,
        roundsDone: 7,
        plannedRounds: 8,
        incomplete: true,
      )));
      expect(md, contains('| 7/8 (incompleta) |'));
    });

    test('una sesión fuera de plan se marca en la tabla', () {
      final md = buildReport(withSession(SessionEntry(
        date: DateTime(2026, 9, 18),
        type: SessionType.bloques,
        totalSec: 600,
        warmupSec: 400,
        cooldownSec: 120,
        outOfPlan: true,
      )));
      expect(md, contains('| Bloques ⚠ fuera de plan |'));
    });
  });

  group('regla de progresión', () {
    test('subir de ronda con series partidas genera alerta', () {
      final base = weekFour();
      final input = ReportInput(
        programStart: base.programStart,
        rangeStart: base.rangeStart,
        rangeEnd: base.rangeEnd,
        today: base.today,
        planVersions: base.planVersions,
        roundsBeforeRange: const {SessionType.circuito: 6},
        sessions: [
          SessionEntry(
            date: DateTime(2026, 9, 16),
            type: SessionType.circuito,
            roundsDone: 7,
            sets: [const SetEntry(exercise: 'Flexiones', setIndex: 1, reps: 10, split: true)],
          ),
        ],
      );
      expect(
        buildAlerts(ReportStats(input)),
        contains('Subiste de 6 a 7 rondas el 16 sep sin cumplir la regla de progresión (series partidas)'),
      );
    });

    test('subir de ronda limpio no genera alerta', () {
      final base = weekFour();
      final input = ReportInput(
        programStart: base.programStart,
        rangeStart: base.rangeStart,
        rangeEnd: base.rangeEnd,
        today: base.today,
        roundsBeforeRange: const {SessionType.circuito: 6},
        sessions: [
          SessionEntry(
            date: DateTime(2026, 9, 16),
            type: SessionType.circuito,
            roundsDone: 7,
            techniqueOk: true,
            fullRange: true,
            recoveryOk: true,
            sets: [const SetEntry(exercise: 'Flexiones', setIndex: 1, reps: 10)],
          ),
        ],
      );
      expect(buildAlerts(ReportStats(input)).where((a) => a.startsWith('Subiste')), isEmpty);
    });

    test('técnica o recuperación marcadas en no también bloquean', () {
      final base = weekFour();
      final input = ReportInput(
        programStart: base.programStart,
        rangeStart: base.rangeStart,
        rangeEnd: base.rangeEnd,
        today: base.today,
        roundsBeforeRange: const {SessionType.progresion: 7},
        sessions: [
          SessionEntry(
            date: DateTime(2026, 9, 18),
            type: SessionType.progresion,
            roundsDone: 8,
            techniqueOk: false,
            recoveryOk: false,
          ),
        ],
      );
      expect(
        buildAlerts(ReportStats(input)).firstWhere((a) => a.startsWith('Subiste')),
        contains('(técnica, recuperación)'),
      );
    });
  });

  group('semana en curso', () {
    ReportInput midWeek({required int todayDay, List<SessionEntry> sessions = const []}) {
      final start = DateTime(2026, 8, 26);
      final w = weekRange(start, 4);
      return ReportInput(
        programStart: start,
        rangeStart: w.start,
        rangeEnd: w.end,
        today: DateTime(2026, 9, todayDay),
        planVersions: [
          PlanVersionInfo(number: 1, validFrom: start, dayTypes: {
            1: DayType.circuito,
            3: DayType.circuito,
            5: DayType.circuito,
          }),
        ],
        sessions: sessions,
      );
    }

    test('a mitad de semana, los días que no han llegado no son faltas', () {
      // mié 16 C (hecha), vie 18 C (hoy, aún no), lun 21 C (futuro).
      final input = midWeek(todayDay: 18, sessions: [
        SessionEntry(date: DateTime(2026, 9, 16), type: SessionType.circuito, warmupSec: 400, cooldownSec: 120),
      ]);
      final s = ReportStats(input);
      expect(s.expectedTraining, 3);
      expect(s.expectedTrainingClosed, 1);
      expect(buildAlerts(s).where((a) => a.startsWith('Sesiones por debajo')), isEmpty);
      expect(buildReport(input), contains('- Sesiones: 1/3 (quedan 2 en el plan)'));
    });

    test('un día de entrenamiento ya cerrado sin sesión sí es falta', () {
      final input = midWeek(todayDay: 19); // mié 16 y vie 18 ya pasaron.
      expect(
        buildAlerts(ReportStats(input)),
        contains('Sesiones por debajo del plan: 0 de 2 en los días ya cerrados'),
      );
    });

    test('una ronda estimada no es récord', () {
      final input = midWeek(todayDay: 22, sessions: [
        SessionEntry(date: DateTime(2026, 9, 16), type: SessionType.circuito, roundsDone: 7),
        SessionEntry(date: DateTime(2026, 9, 18), type: SessionType.circuito, roundsDone: 9, roundsEstimated: true),
      ]);
      expect(ReportStats(input).maxRoundsInRange, 7);
    });
  });

  group('informe markdown', () {
    test('encabezado, resumen y secciones', () {
      final md = buildReport(weekFour(notes: 'Semana pesada en la oficina'));
      expect(md, startsWith('# Informe semanal — 16 sep a 22 sep 2026\n'
          'Semana 4 desde inicio (26 ago) · Plan v1 (desde 26 ago) → v2 (desde 20 sep)'));
      expect(md, contains('- Sesiones: 3/3 · Fútbol: 1/2'));
      expect(md, contains('- Récord de rondas: 8 (anterior: 7)'));
      expect(md, contains('- Días bajo 2.000 kcal: 2'));
      expect(md, contains('| vie 18 sep 15:10 | Circuito | 20:00 | 9:00 / 3:00 | 8:00 | 8 | 8 | 1 | Oficina \\| fútbol intenso ayer |'));
      expect(md, contains('| mié 16 sep 07:00 | Circuito | 18:20 | 5:00 / 2:00 | 11:20 | ~6 (est.) |'));
      expect(md, contains('- Flexiones: 15 · 15 · 12+3 (partida) (fallo)'));
      expect(md, contains('- Vueltas: 2:30 · 2:40 · 2:50 (media 2:40)'));
      expect(md, contains('| mié 16 sep | 216 · 19 g | 1.500 · 50 g | — | — | 1.716 ⚠ | 69 g |'));
      expect(md, contains('| sáb 19 sep | — | — | — | — | sin registro | — |'));
      expect(md, contains('## Fútbol'));
      expect(md, contains('| jue 17 sep | 5 | 60 | 7.200 | 8 | 6 | — |'));
      expect(md, contains('- Peso promedio: 71,2 kg (en ayunas, 2 pesajes) · Δ vs línea base: -1,1 kg'));
      expect(md, isNot(contains('## Medidas')));
      expect(md, endsWith('## Notas de la semana\nSemana pesada en la oficina'));
    });

    test('medidas en la unidad elegida con Δ vs línea base', () {
      final input = weekFour(measurements: [
        MeasurementEntry(date: DateTime(2026, 9, 18), site: MeasureSite.abdomen, valueCm: 84),
      ]);
      final md = buildReport(input);
      expect(md, contains('| Abdomen (ombligo) | 86 (26 ago) | 84 | -2 |'));
      expect(md, contains('| Peso (kg) | 72,3 (26 ago) | 71 | -1,3 |'));
    });

    test('dice de dónde salen las kcal', () {
      final md = buildReport(weekFour(meals: [
        MealEntry(date: DateTime(2026, 9, 16), slot: MealSlot.desayuno, items: const [
          MealItemEntry(label: 'Leche', macros: Macros(kcal: 600, protein: 30), sourceVerified: true),
          MealItemEntry(label: 'Klim', macros: Macros(kcal: 300, protein: 10), sourceVerified: false),
          MealItemEntry(label: 'Bandeja', macros: Macros(kcal: 100, protein: 5)),
        ]),
      ]));
      expect(
        md,
        contains('Procedencia de las kcal: 60% de etiqueta · 30% de tablas de referencia · 10% estimado a ojo'),
      );
    });

    test('rango vacío no revienta', () {
      final start = DateTime(2026, 8, 26);
      final md = buildReport(ReportInput(
        programStart: start,
        rangeStart: start,
        rangeEnd: addDays(start, 6),
        today: start,
      ));
      expect(md, contains('Sin plan'));
      expect(md, contains('Sin sesiones registradas.'));
      expect(md, contains('Sin comidas registradas.'));
      expect(md, contains('- Nutrición: sin registros'));
    });
  });
}
