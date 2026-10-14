import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/mascot_message.dart';

/// Plan 049, slice 3: la frase de Rayito sale de datos reales del día.
void main() {
  String say(int streak, {bool active = false, bool rest = false}) =>
      mascotMessage(streak: streak, activeToday: active, restAdvised: rest);

  test('hoy registrado: suma; si justo cambió de fase, lo celebra', () {
    expect(say(5, active: true),
        'Hoy ya sumaste. 5 días seguidos construyendo tu mejor versión.');
    expect(say(1, active: true),
        '¡Rayito subió al nivel 2! 1 día construyendo tu mejor versión.');
    expect(say(7, active: true),
        '¡Rayito subió al nivel 4! 7 días construyendo tu mejor versión.');
    expect(say(30, active: true),
        '¡Rayito subió al nivel 7! 30 días construyendo tu mejor versión.');
  });

  test('pendiente hoy: dice qué gana con registrar, sin culpar', () {
    expect(say(4), 'Guarda un registro hoy y llegas a 5 días.');
    expect(say(6), 'Guarda un registro hoy y Rayito sube al nivel 4.');
    expect(say(59), 'Guarda un registro hoy y Rayito sube al nivel 8.');
    expect(say(0),
        'Cualquier registro despierta a Rayito. Empieza a tu ritmo.');
  });

  test('descanso indicado por 032: no presiona y recuerda que lo suave cuenta',
      () {
    expect(say(9, rest: true),
        'Descansar también es parte del plan. Registrar tu comida o tu sueño también cuenta.');
    expect(say(9, active: true, rest: true), startsWith('Hoy ya sumaste.'));
  });

  test('ninguna frase culpa', () {
    for (final s in [0, 1, 6, 13, 29, 59, 90]) {
      for (final active in [true, false]) {
        for (final rest in [true, false]) {
          final text = say(s, active: active, rest: rest).toLowerCase();
          for (final word in [
            'perdiste',
            'fallaste',
            'decepcion',
            'abandon',
            'culpa'
          ]) {
            expect(text, isNot(contains(word)), reason: '$s/$active/$rest');
          }
        }
      }
    }
  });
}
