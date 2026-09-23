# Cronómetro guiado

El cronómetro no es un contador genérico: lee el plan del día y sabe si toca
**circuito** (rondas) o **bloques** (series). Ese era el origen de un dato
inválido — un día de bloques quedó registrado como 11 rondas de circuito y el
informe lo tomó como récord.

## Cómo se arma la sesión

[`lib/domain/session_script.dart`](../lib/domain/session_script.dart) convierte
el día del plan en una lista de pasos. Es lógica pura y probada
([`test/domain/session_script_test.dart`](../test/domain/session_script_test.dart)),
así que el comportamiento no depende de la pantalla.

| Tipo de día | Cómo se recorre | Descansos |
|---|---|---|
| Circuito / ligero / progresión | N rondas; cada ronda pasa por todos los ejercicios seguidos | Solo al cerrar la ronda (30 s del plan). Dentro de la ronda, ninguno |
| Bloques | Se agotan las series de un ejercicio antes de pasar al siguiente | El del ejercicio, con rango si el plan lo da (90–120 s) |
| Bloques extra (core, cuádriceps, hombro) | Van después del trabajo principal, en formato de series | El del ejercicio |

Cuando un bloque alterna variantes (core A/B), se elige al empezar y el guion
solo incluye la elegida.

## Durante la sesión

- Pantalla grande con **ejercicio, objetivo y contador**: "Ronda 3/7" o
  "Serie 2/4 · Flexiones 14–16".
- Un botón **Hecho** avanza. Las repeticiones vienen prellenadas con el objetivo
  y se ajustan con −/+ si hiciste otra cosa.
- Al cerrar un paso con descanso, arranca la **cuenta regresiva automática** con
  la duración del plan, muestra qué viene después y avisa con sonido y vibración
  al terminar. Se puede saltar.
- **Fases explícitas**: la sesión empieza en calentamiento, se marca el inicio
  del trabajo y termina en enfriamiento. La app calcula sola calentamiento,
  trabajo neto y enfriamiento; no hay que escribirlos.
- La pantalla no se apaga (wakelock).
- **Terminar antes** cierra la sesión con lo hecho hasta ahí y la marca como
  incompleta. Paraste en la ronda 7 de 8: eso es un dato, no un error.

Al final, un resumen con tiempos, rondas o series completadas y tiempo por
ronda, y de ahí al formulario con todo prellenado para añadir RPE, contexto y
notas.

## Límite conocido

El aviso de fin de descanso **suena solo con la app en primer plano**: usa el
sonido del sistema y la vibración. Para que avise con la pantalla apagada hacen
falta notificaciones locales, que van en la siguiente fase
([roadmap](roadmap.md)).

## Sin plan para hoy

Si el día no tiene ejercicios planificados, la app ofrece el **cronómetro
libre** (el anterior): mide tiempos y cuenta vueltas genéricas, pero registra
la sesión como tipo "Otro" para que nunca entre al récord de rondas.

Si el día es de fútbol o descanso y entrenas igual, la sesión queda marcada
como **fuera de plan** y así aparece en el informe.
