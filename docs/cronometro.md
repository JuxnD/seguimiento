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

Tres fases con la **misma forma**: calentamiento → trabajo → enfriamiento.
Calentamiento y enfriamiento tienen pantalla propia, anillo contra la meta del
perfil (calentamiento mínimo y meta de enfriamiento; 6 y 3 min por defecto,
editables en Ajustes) y un botón grande para cerrarlas; nada se salta por
accidente.

- **Calentamiento**: debajo del reloj, "Lo que viene" con los ejercicios, el
  objetivo y el agarre del plan.
- **Trabajo**: contador ("RONDA 3/7" o "SERIE 2/4"), ejercicio, agarre si el
  plan lo pide, y un **anillo con las repeticiones** que se llena al llegar al
  objetivo; −/+ a los lados si hiciste otra cosa. Debajo, qué viene después y
  una barra de avance de la sesión. **Hecho** avanza, con transición animada.
- **Descanso**: cuenta regresiva en un anillo azul con la duración del plan,
  "A continuación" y la barra de avance; avisa con sonido y vibración al
  terminar y se puede saltar. Si el descanso viene de cerrar una ronda, aparece
  la insignia **"Ronda N lista · m:ss"** con el tiempo de esa vuelta.
- **Enfriamiento**: igual que el calentamiento, con "Ya hiciste" (rondas o
  series, repeticiones y neto). Cerrarlo con menos de **1 min** pide
  confirmación: guardar sin enfriar casi siempre es un descuido.
- La app calcula sola calentamiento, trabajo neto (total − calentamiento −
  enfriamiento, la misma cuenta del formulario) y enfriamiento.
- La pantalla no se apaga (wakelock).
- **Terminar antes** cierra la sesión con lo hecho hasta ahí y la marca como
  incompleta. Paraste en la ronda 7 de 8: eso es un dato, no un error.

Al final, una **medalla animada** con una frase basada en el dato real
([`sessionPraise`](../lib/domain/progress.dart)): récord, "+N rondas más que el
lunes", "más rápido", "plan cumplido" o "sesión registrada" si quedó
incompleta. Nunca un "¡buen trabajo!" genérico. Debajo, tiempos, rondas o
series y tiempo por ronda, y de ahí al formulario prellenado para añadir RPE,
"¿qué te costó más?" (chips con los ejercicios de la sesión, "Ninguno" por
defecto) y notas. El formulario no repite la celebración.

## Si Android cierra la app a mitad de sesión

Cada paso (empezar, hecho, ajustar repeticiones, descanso, cerrar fases) deja
una foto del estado en `sesion-en-curso.json`
([`active_session.dart`](../lib/domain/active_session.dart), fuera de la base).
Si la app muere, Hoy y Entreno muestran **"Sesión sin terminar"** con Retomar y
Descartar; empezar otra sesión pregunta antes de pisarla. Al retomar, el reloj
ya contó el tiempo que la app estuvo cerrada (todo son marcas de reloj) y un
descanso en curso vuelve a programar su aviso. El cronómetro libre funciona
igual. La foto se borra al guardar o descartar la sesión.

## Fin del descanso

En primer plano suena el sonido del sistema y vibra. Con la pantalla apagada
avisa una notificación programada con alarma exacta; si Android no la permite
(14+ por defecto), el aviso puede llegar tarde y la app lo dice una vez. Detalle
en [notificaciones.md](notificaciones.md).

## Sin plan para hoy

Si el día no tiene ejercicios planificados, la app ofrece el **cronómetro
libre** (el anterior): mide tiempos y cuenta vueltas genéricas, pero registra
la sesión como tipo "Otro" para que nunca entre al récord de rondas.

Si el día es de fútbol o descanso y entrenas igual, la sesión queda marcada
como **fuera de plan** y así aparece en el informe.
