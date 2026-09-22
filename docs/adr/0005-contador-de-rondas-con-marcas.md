# ADR 0005 — El contador guarda la marca de cada ronda

Fecha: 2026-09-22 · Estado: aceptada

## Contexto

Perder la cuenta de las rondas era el problema real (se contaba con monedas).
La planeación pedía además estimar rondas como `neto ÷ (tiempo medio por ronda
+ 30 s)`, pero no existía ninguna fuente para ese "tiempo medio".

## Decisión

El contador registra, para cada ronda, los segundos transcurridos desde el
inicio del circuito (`session_rounds`). De ahí salen la duración de cada vuelta
y el tiempo medio real. El contador también marca el paso
calentamiento → circuito → enfriamiento, así que esos tiempos no se escriben a
mano. Los tiempos se calculan con marcas de reloj (`DateTime`), no acumulando
ticks de un temporizador.

Cuando la media se toma del historial del contador ya incluye el descanso entre
rondas, así que la estimación usa `descanso = 0`; si el tiempo medio se escribe
a mano (tiempo de trabajo puro), el descanso va aparte, por defecto 30 s.

## Consecuencias

- El informe muestra las vueltas (`2:30 · 2:40 · 2:50 (media 2:40)`), que dicen
  más sobre la fatiga que el total.
- Las rondas estimadas se distinguen de las contadas (`~7 (est.)`) y generan
  alerta.
- Si la app se cierra durante el circuito, la sesión en curso se pierde: el
  estado del contador vive en memoria. Persistirlo queda pendiente
  (ver [roadmap.md](../roadmap.md)).
