import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import '../../app/providers.dart';
import '../../data/database.dart';
import '../../domain/dates.dart';
import '../../ui/widgets.dart';

class KneeHistoryCard extends ConsumerWidget {
  const KneeHistoryCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<MorningCheckRow>>(
        stream: (db.select(db.morningChecks)
              ..orderBy([(t) => OrderingTerm.desc(t.date)])
              ..limit(14))
            .watch(),
        builder: (context, snapshot) =>
            AppCard(title: 'Rodilla en escaleras', children: [
              if (snapshot.hasError)
                Text('Error: ${snapshot.error}')
              else if (!snapshot.hasData)
                const LinearProgressIndicator()
              else if (snapshot.data!.isEmpty)
                const Text('Sin registros. Cero y sin dato son distintos.')
              else ...[
                Semantics(
                    label:
                        'Historial de dolor al despertar, escala 0 a 10. Los días sin dato no se conectan.',
                    child: SizedBox(
                        height: 120,
                        width: double.infinity,
                        child: CustomPaint(
                            painter: _KneePainter(snapshot.data!)))),
                for (final row in snapshot.data!)
                  Text(
                      '${row.date}: ${row.kneeStairs == null ? 'sin dato' : '${row.kneeStairs}/10'}'),
              ],
            ]));
  }
}

class _KneePainter extends CustomPainter {
  _KneePainter(this.rows);
  final List<MorningCheckRow> rows;
  @override
  void paint(Canvas canvas, Size size) {
    final sorted = [...rows]..sort((a, b) => a.date.compareTo(b.date));
    final start = parseDay(sorted.first.date);
    final range = daysBetween(start, parseDay(sorted.last.date));
    final ink = Paint()
      ..color = Colors.lightGreen
      ..strokeWidth = 2;
    Offset? previous;
    DateTime? previousDate;
    for (final row in sorted) {
      final day = parseDay(row.date);
      if (row.kneeStairs == null) {
        previous = null;
        previousDate = null;
        continue;
      }
      final point = Offset(
          6 +
              (size.width - 12) *
                  daysBetween(start, day) /
                  (range == 0 ? 1 : range),
          size.height - 6 - (size.height - 12) * row.kneeStairs! / 10);
      if (previous != null && daysBetween(previousDate!, day) == 1) {
        canvas.drawLine(previous, point, ink);
      }
      canvas.drawCircle(point, 3, ink);
      previous = point;
      previousDate = day;
    }
  }

  @override
  bool shouldRepaint(_KneePainter old) => old.rows != rows;
}
