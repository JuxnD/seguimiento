import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/plan_shift.dart';

void main() {
  // Semana del v3.1: lunes a viernes sesiones, sábado y domingo fútbol.
  final monday = DateTime(2026, 10, 12);
  DateTime day(int i) => addDays(monday, i);
  ShiftDayKind v31(DateTime d) =>
      d.weekday >= DateTime.saturday ? ShiftDayKind.fixed : ShiftDayKind.session;
  List<DateTime?> week(List<DateTime> shifts,
          [ShiftDayKind Function(DateTime)? kind]) =>
      [for (var i = 0; i < 7; i++) shiftedNominal(day(i), shifts, kind ?? v31)];

  test('sin corrimientos cada día muestra su propio contenido', () {
    expect(week(const []), [for (var i = 0; i < 7; i++) day(i)]);
  });

  test('rodar el lunes: el test de torso va el martes y piernas el jueves', () {
    // Caso del owner (semana del 12 oct): torso el martes 13, piernas debía
    // quedar el jueves 15. El viernes se pierde (no hay descanso).
    expect(week([monday]), [null, day(0), day(1), day(2), day(3), day(5), day(6)]);
    expect(shiftedReal(day(2), [monday], v31), day(3));
    expect(shiftedReal(day(0), [monday], v31), day(1));
    expect(shiftDropped(monday, [monday], v31), [day(4)]);
    // Lo que se pierde se queda en su día: un test nunca desaparece.
    expect(shiftedReal(day(4), [monday], v31), day(4));
  });

  test('el día libre sabe qué pasó a mañana y si se pierde', () {
    expect(vacatedContent(monday, [monday], v31), monday);
    expect(shiftedRealOrNull(monday, [monday], v31), day(1));
    expect(vacatedContent(day(1), [monday], v31), isNull);
    // Rodar el viernes: no hay otro día de sesión esa semana.
    expect(vacatedContent(day(4), [day(4)], v31), day(4));
    expect(shiftedRealOrNull(day(4), [day(4)], v31), isNull);
    // Dos veces: el martes libre tenía el lunes, que ahora va el miércoles.
    expect(vacatedContent(day(1), [monday, day(1)], v31), day(0));
    expect(shiftedRealOrNull(day(0), [monday, day(1)], v31), day(2));
  });

  test('rodar el jueves sólo mueve el jueves al viernes', () {
    expect(week([day(3)]), [day(0), day(1), day(2), null, day(3), day(5), day(6)]);
  });

  test('rodar dos veces corre dos días', () {
    expect(week([monday, day(1)]), [null, null, day(0), day(1), day(2), day(5), day(6)]);
    expect(shiftDropped(monday, [monday, day(1)], v31), [day(3), day(4)]);
  });

  test('el primer descanso absorbe el corrimiento y no se pierde nada', () {
    ShiftDayKind kind(DateTime d) => switch (d.weekday) {
          DateTime.wednesday || DateTime.sunday => ShiftDayKind.rest,
          DateTime.saturday => ShiftDayKind.fixed,
          _ => ShiftDayKind.session,
        };
    expect(week([monday], kind), [null, day(0), day(1), day(3), day(4), day(5), day(6)]);
    expect(shiftDropped(monday, [monday], kind), isEmpty);
  });

  test('el fútbol no se mueve y la cadena lo salta', () {
    ShiftDayKind kind(DateTime d) =>
        d.weekday == DateTime.tuesday || d.weekday >= DateTime.saturday
            ? ShiftDayKind.fixed
            : ShiftDayKind.session;
    expect(week([monday], kind), [null, day(1), day(0), day(2), day(3), day(5), day(6)]);
  });

  test('rodar un día sin sesión no cambia nada', () {
    expect(week([day(5)]), week(const []));
  });

  test('la semana siguiente vuelve a lo normal', () {
    final next = addDays(monday, 7);
    expect(shiftedNominal(next, [monday], v31), next);
    expect(shiftedNominal(addDays(next, 3), [monday, day(1)], v31), addDays(next, 3));
  });
}
