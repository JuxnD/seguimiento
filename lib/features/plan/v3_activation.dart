import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/seed_plan.dart';
import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../domain/plan_v3.dart';
import '../../ui/widgets.dart';

/// Activa el v3.1 desde `monday` tras confirmar. Cambia las metas de comida a
/// las de §19.3: se dice antes.
Future<void> activateV31(BuildContext context, WidgetRef ref, DateTime monday) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Plan v3.1 desde el ${weekdayShort(monday.weekday)} ${formatShort(monday)}'),
      content: Text('Se crea la versión nueva del plan; la actual sigue hasta el domingo anterior. '
          'Metas: ${fmtInt(v31KcalWeekday)} kcal entre semana, ${fmtInt(v31KcalFootball)} en días de fútbol, '
          'proteína $v31ProteinMin–$v31ProteinMax g. '
          'Abdomen en ayunas el ${formatShort(v31MeasurementDates(monday).first)} y luego cada 2 semanas. '
          'Pruebas: ${formatShort(v31TestDate(monday))}.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Activar')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await guarded(
    context,
    () => activatePlanV31(ref.read(databaseProvider), ref.read(planRepositoryProvider), monday),
    ok: 'Plan v3.1 activo desde el ${formatShort(monday)}',
  );
  ref.invalidate(dashboardProvider);
  ref.invalidate(profileProvider);
}

/// Activa el v3 desde `monday` tras confirmar.
Future<void> activateV3(BuildContext context, WidgetRef ref, DateTime monday) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Plan v3 desde el ${weekdayShort(monday.weekday)} ${formatShort(monday)}'),
      content: Text('Se crea la versión 3 del plan. El v2 sigue hasta el domingo anterior. '
          'Próxima medición: ${formatShort(v3MeasurementDates(monday).first)} en ayunas. '
          'Test final: ${formatShort(v3TestDate(monday))}.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Activar')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await guarded(
    context,
    () => activatePlanV3(ref.read(databaseProvider), ref.read(planRepositoryProvider), monday),
    ok: 'Plan v3 activo desde el ${formatShort(monday)}',
  );
  ref.invalidate(dashboardProvider);
}
