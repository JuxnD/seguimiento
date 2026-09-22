// Genera el ejemplo de informe de docs/ejemplo-informe.md con datos ficticios.
//
//   dart run tool/sample_report.dart > docs/ejemplo-informe.md
//
// Sirve para ver cómo queda el producto sin abrir la app.
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/domain/report/report_input.dart';

void main() {
  final start = DateTime(2026, 8, 26);
  final week = weekRange(start, 4);
  DateTime d(int day) => DateTime(2026, 9, day);

  SetEntry set(String ex, int i, int reps, {bool split = false, String? detail, bool fail = false}) =>
      SetEntry(exercise: ex, setIndex: i, reps: reps, split: split, splitDetail: detail, toFailure: fail);

  final input = ReportInput(
    programStart: start,
    rangeStart: week.start,
    rangeEnd: week.end,
    today: d(22),
    planVersions: [
      PlanVersionInfo(number: 1, validFrom: start, dayTypes: {
        1: DayType.circuito,
        2: DayType.futbol,
        3: DayType.circuito,
        4: DayType.futbol,
        5: DayType.circuito,
      }),
    ],
    previousRoundsRecord: 7,
    sessions: [
      SessionEntry(
        date: d(16),
        startTime: '07:00',
        type: SessionType.circuito,
        totalSec: 1100,
        warmupSec: 300,
        cooldownSec: 120,
        roundsDone: 6,
        roundsEstimated: true,
        rpe: 7,
        context: 'Dormí 5 h',
        sets: [set('Flexiones', 1, 12, split: true, detail: '8+4'), set('Sentadillas', 1, 20)],
      ),
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
        context: 'Oficina, fútbol intenso ayer',
        notes: 'La 6ª con margen',
        lapsSec: [150, 160, 170],
        sets: [
          set('Flexiones', 1, 15),
          set('Flexiones', 2, 15),
          set('Flexiones', 3, 15, split: true, detail: '12+3', fail: true),
          set('Sentadillas', 1, 20),
        ],
      ),
    ],
    football: [
      FootballEntry(date: d(17), format: 5, minutes: 60, steps: 7200, intensity: 8, fatigueAfter: 6),
      FootballEntry(date: d(22), format: 7, minutes: 75, steps: 9100, intensity: 9, fatigueAfter: 7),
    ],
    meals: [
      MealEntry(date: d(16), slot: MealSlot.desayuno, time: '07:40', items: const [
        MealItemEntry(label: 'Huevo', quantityLabel: '×3', macros: Macros(kcal: 216, protein: 19, fat: 14)),
        MealItemEntry(label: 'Klim', quantityLabel: '25 g', macros: Macros(kcal: 125, protein: 6, carbs: 10, fat: 7)),
      ]),
      MealEntry(date: d(16), slot: MealSlot.almuerzo, time: '13:00', items: const [
        MealItemEntry(label: 'Bandeja', macros: Macros(kcal: 1100, protein: 55, carbs: 90, fat: 45)),
      ]),
      MealEntry(date: d(17), slot: MealSlot.desayuno, time: '07:30', items: const [
        MealItemEntry(label: 'Huevo', quantityLabel: '×3', macros: Macros(kcal: 216, protein: 19, fat: 14)),
      ]),
      MealEntry(date: d(17), slot: MealSlot.almuerzo, time: '12:50', items: const [
        MealItemEntry(label: 'Arroz', quantityLabel: '200 g', macros: Macros(kcal: 260, protein: 5, carbs: 57)),
        MealItemEntry(label: 'Atún', quantityLabel: '×2', macros: Macros(kcal: 220, protein: 44, fat: 4)),
      ]),
      MealEntry(date: d(18), slot: MealSlot.almuerzo, time: '13:10', items: const [
        MealItemEntry(label: 'Rappi: pollo + papa', macros: Macros(kcal: 1200, protein: 70, carbs: 110, fat: 40)),
      ]),
      MealEntry(date: d(18), slot: MealSlot.cena, time: '20:00', items: const [
        MealItemEntry(label: 'Batido', macros: Macros(kcal: 400, protein: 40, carbs: 35, fat: 8)),
      ]),
    ],
    weightsInRange: [WeightEntry(date: d(16), kg: 71.6), WeightEntry(date: d(20), kg: 71.0)],
    baselineWeight: WeightEntry(date: start, kg: 72.3),
    measurementsInRange: [
      MeasurementEntry(date: d(18), site: MeasureSite.abdomen, valueCm: 84),
      MeasurementEntry(date: d(18), site: MeasureSite.brazoTensionado, valueCm: 34.5),
    ],
    baselineMeasurements: {
      MeasureSite.abdomen: MeasurementEntry(date: start, site: MeasureSite.abdomen, valueCm: 86),
      MeasureSite.brazoTensionado:
          MeasurementEntry(date: start, site: MeasureSite.brazoTensionado, valueCm: 34),
    },
    measurementDatesBefore: [start],
    notes: 'Semana con dos partidos y poca cocina en casa.',
  );

  // ignore: avoid_print
  print(buildReport(input));
}
