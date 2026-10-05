# Plan v3 "Cierre de año"

> Reemplazado por el [Plan v3.1](plan-v3-1.md) (§19, 5 oct) en la semana tipo,
> el calendario, la nutrición y el EMOM de burpees.

Traspaso §18 (3–4 oct 2026). Diez semanas desde un lunes hasta el test final
(viernes de la semana 10: 18 dic si se empieza el 12 oct). Objetivo: físico
proporcionado (espalda en V, hombro, brazos, abdomen) manteniendo la
resistencia.

## Cómo se activa

- **Hoy** lo propone ("¡10 rondas limpias!") cuando la última progresión fue
  de 10 rondas o más y cumple la regla (técnica, rango y recuperación en
  "Sí", sin series partidas ni fallo). El arranque es el lunes siguiente a
  esa sesión.
- **Plan semanal** tiene *Activar desde el …* y *Otro lunes* mientras no haya
  v3.
- Activar crea la versión con `scheme = 'v3'`
  ([`seed_plan.dart`](../lib/data/seed_plan.dart), `planV3` y
  `activatePlanV3`), completa las guías de los ejercicios nuevos y fija la
  próxima medición en el viernes de la semana 4. El v2 rige hasta el domingo
  anterior.

## Semana tipo (§18.2)

| Día | Tipo | Qué |
|---|---|---|
| Lunes | Tren superior | A: tirón y hombro + core (elevaciones, hollow) |
| Martes | Piernas | búlgara, peso muerto a una pierna, puente, gemelos, Pallof, plancha lateral (todo por lado) |
| Miércoles | Resistencia | Cindy (AMRAP 20 min) o Tabata (4 × 8 × 20/10), según la semana |
| Jueves | Tren superior | B: empuje y brazos; curl + extensión de tríceps en **superserie** |
| Viernes | Densidad | circuito ligero de 6 rondas, L-sit, toes-to-bar y el **EMOM de burpees** |
| Sáb/dom | Fútbol | si el domingo fue ≥ 8, el lunes en versión ligera |

## Periodización (§18.6) — [`plan_v3.dart`](../lib/domain/plan_v3.dart)

- Semana del bloque desde la **primera** versión v3: editar el plan a mitad
  de bloque no reinicia las semanas.
- Fases: 1–3 acumulación, 4 descarga, 5–7 intensificación, 8 descarga, 9–10
  pico.
- Volumen reducido (una serie menos por ejercicio de series, sin lastre;
  `deloadVersion`): semanas 4 y 8, y lunes a miércoles de la 10. El
  cronómetro lo aplica solo y lo anota en la sesión; Hoy lo avisa.
- Miércoles: Cindy las semanas impares y Tabata las pares; la 4 y la 10 son
  Cindy (test) y la 8 son las 10 rondas por tiempo. El traspaso dice a la vez
  "test de Cindy el miércoles de la semana 4" y "10 rondas por tiempo en las
  descargas": se resolvió así (Cindy en la 4, por tiempo en la 8). Al
  empezar se puede elegir otro formato.
- Burpees EMOM del viernes: 6 × 6 (semanas 1–3), 8 × 8 (5–7), 10 × 10 (9);
  sin burpees en descarga ni en la semana del test. Si un minuto no sale, el
  resto va con el escalón anterior (10 → 8 → 6 → 5).
- Hoy muestra "Cierre de año · semana N de 10 · fase" y la cuenta atrás al
  test.

## Cronómetros nuevos — [`v3_timers.dart`](../lib/features/training/v3_timers.dart)

- **Cindy**: calentamiento (meta 8 min), 20 min con "+1 ronda", al final las
  reps de la ronda a medias, enfriamiento. Guarda rondas (`roundsDone`), reps
  sueltas (`extraReps`), las series por ejercicio y `mode = 'cindy'`.
- **Tabata**: 4 bloques de 8 × (20 s / 10 s) con 1 min entre bloques (16:10);
  suena al cambiar de tramo. En el minuto entre bloques pide las reps del
  peor intervalo, que es la métrica. `mode = 'tabata'`.
- **10 rondas por tiempo**: el cronómetro de siempre con 10 rondas y 30 s;
  la métrica es el trabajo neto. `mode = 'porTiempo'`.
- **EMOM**: un pitido al empezar cada minuto, "6 hechos" o "No llegué". Se
  suma a la sesión de densidad del día (o la crea).

Las sesiones de Cindy y Tabata se guardan solas como "sin revisar" y luego
se abre el formulario, igual que el cronómetro (§16.9).

## Otros

- **Superseries** (`plan_exercises.superset_group`): A1 → B1 → descanso →
  A2 → B2.
- **Variante por serie** (`session_sets.variant`, §18.4): si el ejercicio
  tiene cadena de progresión ("arquero → una mano con mano elevada → …"), el
  cronómetro muestra "Variante: …" con la última usada y la guarda en cada
  serie; el informe la escribe entre paréntesis.
- **Banda elástica** (§18.7): `exercises.anchor` ('alto', 'medio', 'bajo',
  'manos'); la hoja de técnica explica el anclaje del ejercicio y abre la
  guía completa (anclajes, tensión, seguridad).

## Pendiente

- Récord propio de Cindy y gráfica de Cindy por semana.
- Retomar Cindy, Tabata o EMOM si Android cierra la app a mitad (hoy se
  pierden; el cronómetro guiado sí se retoma).
- Test final del 18 dic como pantalla propia (hoy Hoy lo anuncia y se
  registra con el formulario de sesión).
