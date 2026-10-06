import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/ai_report_sources.dart';
import 'package:seguimiento/domain/ai_context.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/report/report_input.dart';

void main() {
  final current = ReportInput(
    programStart: DateTime(2026, 9, 1),
    rangeStart: DateTime(2026, 10, 5),
    rangeEnd: DateTime(2026, 10, 11),
    today: DateTime(2026, 10, 11),
    sessions: [
      SessionEntry(
        date: DateTime(2026, 10, 6),
        type: SessionType.circuito,
        totalSec: 1200,
        sets: [const SetEntry(exercise: 'Flexiones', setIndex: 1, reps: 12)],
      ),
    ],
    meals: [
      MealEntry(
        date: DateTime(2026, 10, 6),
        slot: MealSlot.almuerzo,
        items: [
          const MealItemEntry(
            label: 'Arroz',
            macros: Macros(kcal: 200, protein: 4, carbs: 40, fat: 1),
          ),
        ],
      ),
    ],
    weightsInRange: [
      WeightEntry(date: DateTime(2026, 10, 6), kg: 70),
    ],
    measurementsInRange: [
      MeasurementEntry(
        date: DateTime(2026, 10, 6),
        site: MeasureSite.abdomen,
        valueCm: 85,
      ),
    ],
    notes: 'nota corporal privada',
    steps: {DateTime(2026, 10, 6): 7000},
    sleep: {DateTime(2026, 10, 6): 7.5},
  );

  test('conserva exactamente el informe seleccionado por defecto', () {
    const report = '# Informe semanal\nPeso en ayunas: 70 kg';
    final sources = reportQuestionSources(input: current, report: report);

    expect(sources, hasLength(1));
    expect(sources.single.id, 'report_current');
    expect(sources.single.text, report);
    expect(sources.single.text, contains('70 kg'));
  });

  test('cita peso actual sin poder atribuir el del periodo anterior', () {
    final sources = reportQuestionSources(
      input: current,
      report: '# Informe\nPeso actual: 70 kg',
    );
    final snapshot = AiConversationSnapshot(
      kind: AiConversationKind.reportQuestion,
      title: 'Informe',
      sources: sources,
      model: aiQuestionModel,
      contractVersion: aiQuestionContractVersion,
    );
    validateAiAnswer(
      snapshot: snapshot,
      answer: 'El informe actual registra el dato citado.',
      citations: const [
        AiCitation(sourceId: 'report_current', quote: 'Peso actual: 70 kg')
      ],
      contractVersion: aiQuestionContractVersion,
    );
    expect(
      () => validateAiAnswer(
        snapshot: snapshot,
        answer: 'El informe actual registra el dato citado.',
        citations: const [
          AiCitation(
              sourceId: 'local_previous_comparison',
              quote: 'Peso anterior: 72 kg')
        ],
        contractVersion: aiQuestionContractVersion,
      ),
      throwsFormatException,
    );
  });

  test('añade comparación del periodo previo solo si se elige', () {
    final previous = ReportInput(
      programStart: DateTime(2026, 9, 1),
      rangeStart: DateTime(2026, 9, 28),
      rangeEnd: DateTime(2026, 10, 4),
      today: DateTime(2026, 10, 4),
      sessions: [
        SessionEntry(
          date: DateTime(2026, 9, 30),
          type: SessionType.circuito,
          totalSec: 800,
        ),
      ],
    );
    final withPrevious = ReportInput(
      programStart: current.programStart,
      rangeStart: current.rangeStart,
      rangeEnd: current.rangeEnd,
      today: current.today,
      previous: previous,
    );
    final sources = reportQuestionSources(
      input: withPrevious,
      report: '# Informe actual',
      includePrevious: true,
    );

    expect(sources, hasLength(2));
    expect(sources.last.text, contains('Comparación local calculada'));
    expect(sources.last.text, contains('frente a'));
    expect(() => reportQuestionSources(input: withPrevious, report: '# Actual'),
        returnsNormally);
  });
}
