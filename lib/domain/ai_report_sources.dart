import 'dart:convert';

import 'ai_context.dart';
import 'dates.dart';
import 'report/period_summary.dart';
import 'report/report_input.dart';

/// Conserva el texto exacto del informe visible. Solo añade una fuente
/// comparativa estructurada si el usuario la elige expresamente.
List<AiContextSource> reportQuestionSources({
  required ReportInput input,
  required String report,
  bool includePrevious = false,
}) {
  final sources = <AiContextSource>[
    AiContextSource(
      id: 'report_current',
      title: 'Informe seleccionado',
      text: report,
    ),
  ];
  if (includePrevious) {
    final summary = summarizePeriod(input);
    final previous = summary.previous;
    if (previous == null) {
      throw const FormatException(
          'Este rango no tiene un periodo anterior comparable.');
    }
    final compare = StringBuffer()
      ..writeln(
          'Comparación local calculada · ${dayKey(summary.from)} a ${dayKey(summary.to)} frente a ${dayKey(previous.from)} a ${dayKey(previous.to)}')
      ..writeln(
          'Sesiones: ${summary.trainingSessions} frente a ${previous.trainingSessions}.')
      ..writeln('Pasos: ${summary.stepsTotal} frente a ${previous.stepsTotal}.')
      ..writeln(
          'Días de comida cerrados: ${summary.closedDays} frente a ${previous.closedDays}.');
    for (final exercise in summary.exercises) {
      compare.writeln(
          '${exercise.name}: ${exercise.amount} frente a ${exercise.previous ?? 0} ${exercise.isHold ? 'segundos' : 'repeticiones'}.');
    }
    if (previous.avgKcalIn case final kcal?) {
      compare.writeln(
          'Promedio de comida anterior: ${kcal.toStringAsFixed(0)} kcal.');
    }
    if (previous.avgProtein case final protein?) {
      compare.writeln(
          'Promedio de proteína anterior: ${protein.toStringAsFixed(1)} g.');
    }
    sources.add(AiContextSource(
      id: 'local_previous_comparison',
      title: 'Comparación anterior calculada en la app',
      text: compare.toString().trim(),
    ));
  }
  validateAiSources(sources);
  return sources;
}

int reportSourcesBytes(List<AiContextSource> sources) => utf8
    .encode(jsonEncode([for (final source in sources) source.toJson()]))
    .length;
