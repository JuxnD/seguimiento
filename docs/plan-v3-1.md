# Plan v3.1

Traspaso §19 (5 oct 2026). Reemplaza la semana tipo, el calendario, la
nutrición y el EMOM de burpees del [Plan v3](plan-v3.md). Siguen vigentes la
guía de la banda, las cadenas de progresión, el bloque de compresión y los
cronómetros de Cindy y Tabata.

## Cómo se activa

- **Hoy** muestra "Plan v3.1 listo" con el próximo lunes mientras no haya
  v3.1. No espera las 10 rondas limpias: el viernes sigue siendo el circuito
  hasta lograrlas.
- **Plan semanal** tiene *Activar desde el …* y *Otro lunes*.
- Activar ([`seed_plan.dart`](../lib/data/seed_plan.dart), `planV31` y
  `activatePlanV31`):
  - crea la versión con `scheme = 'v3.1'`;
  - completa las guías de los ejercicios nuevos;
  - pone las metas de §19.3: 2.100 kcal entre semana, 2.400 en días de
    fútbol, proteína: mínimo 130 g, objetivo 140–160 g (ajuste del 7 oct);
  - fija la próxima medición en el sábado de la semana 1.
- Un v3 activado para el mismo lunes queda reemplazado, porque a igual fecha
  gana la versión más nueva. La semana del bloque cuenta desde la primera
  versión v3.1.

## Semana tipo (§19.1)

| Día | Tipo | Qué |
|---|---|---|
| Lunes | Tren superior | Pino 5 min, dominadas con mochila, remo + laterales en superserie, pike, face pull, elevaciones colgado, rollout, peldaño del dragon flag. Después, caminata de 15–20 min |
| Martes | Tren superior | Pino, fondos con mochila, flexión a una mano 3 × 3–4 por lado (luego 3 × 4–5), diamante con mochila 3 × 8–12, tríceps + curl en superserie, colgarse de la barra |
| Miércoles | Piernas | FIFA 11+ como calentamiento, saltos, aceleraciones, búlgara, peso muerto a una pierna, nórdicos, gemelos, carga de maleta, core (Pallof + plancha lateral) |
| Jueves | Tren superior | Torso B; compresión (A) o L-sit (B) en semanas alternas; pistol opcional |
| Viernes | Progresión → Resistencia | Pino, circuito 5/10/15 hasta 10 rondas limpias, habilidades ligeras. Después, Cindy y Tabata de bajo impacto alternos |
| Sáb/dom | Fútbol | FIFA 11+ y aceleraciones antes; hidratación |

- **Pino** (bloque `pino`): va antes del trabajo principal, sin fatiga. Se
  muestra en minutos.
- **Calentamiento del día** (bloque `calentamiento`): no es un paso del
  cronómetro. La fase de calentamiento lo muestra con su técnica.
- **Tabata** (bloque `tabata`): solo lo recorre su cronómetro. Es de bajo
  impacto: flexiones, escaladores, sentadillas, hollow rocks.

## Viernes — [`plan_v3.dart`](../lib/domain/plan_v3.dart), `v31Friday`

- Mientras no haya 10 rondas limpias, es el circuito de progresión con la
  meta de la regla. Limpias quiere decir que se cumplen todos los criterios
  de §2; lo comprueba `TrainingRepository.firstCleanTen`.
- A partir del viernes siguiente a las 10 limpias alterna **Cindy** y
  **Tabata**, empezando por Cindy:
  - la primera Cindy es la de prueba (línea base) y se repite como prueba
    cada 4 semanas;
  - el viernes de pruebas siempre es Cindy.
- Hoy cambia el día a "Resistencia" y el cronómetro ofrece el formato de la
  semana.
- Si hubo partido de lunes a jueves, Hoy avisa que el partido reemplaza la
  sesión metabólica.

## Calendario (§19.4)

- **9 semanas:**
  - semanas 1–5: bloque 1;
  - semana 6: descarga (mitad de series redondeando hacia arriba, sin lastre
    extra);
  - semanas 7–9: bloque 2;
  - pruebas el viernes de la semana 9 (11 dic).
- Semana 1: Hoy recuerda trabajar a RIR 2–3 para aprender los patrones.
- **Mediciones:** abdomen en ayunas cada 2 semanas en sábado (17 oct, 31 oct,
  14 nov, 28 nov, 12 dic). El 14 nov y el 12 dic son medidas completas.
  - Al guardar una medición, la próxima pasa a la siguiente fecha
    (`advanceV31Measurement`).
  - Las fechas del calendario no avisan "antes de tiempo".

## Fuerza (§19.2)

- **RIR por serie** (`session_sets.rir`, 0–5): en el descanso, después de cada
  serie de fuerza ("¿cuántas te quedaban?"); la última se anota en el
  enfriamiento. El informe lo escribe junto a la serie.
- **Doble progresión** (`doubleProgressionHint`): si la última vez del mismo
  día de la semana todas las series llegaron al tope del rango sin RIR 0, el
  cronómetro muestra "Toca subir". Cómo se sube:
  - con mochila, +2–5 kg;
  - si no, el siguiente escalón de la cadena;
  - si no hay cadena, más banda o una pausa.
- Las dominadas llevan carga (mochila). El cronómetro la pide en las series,
  no en las rondas del circuito.

## Guía de ejercicios v3.1

[`exercise_details.dart`](../lib/data/exercise_details.dart) tiene, por
ejercicio:
- qué trabaja;
- el paso a paso;
- los errores comunes;
- cómo hacerlo más fácil o más difícil;
- avisos.

Es la "Guía de ejercicios v3.1" del usuario. La hoja de técnica lo muestra;
las claves cortas del catálogo siguen en `exercises.form_cues`. Algunas
unidades no son repeticiones (metros, saltos, sprints) y se muestran así.

## Hábitos (§19.3, §19.6) — [`habits.dart`](../lib/domain/habits.dart)

- **Meta de kcal por día:** sábado y domingo usan
  `profiles.kcal_target_football`; si está vacío, la de entre semana. Se
  edita en Ajustes.
- **Sueño** (`sleep_logs`): hasta las 2 p. m., Hoy pregunta las horas en cama
  de anoche. El informe da el promedio y las noches de 8 h o más.
- **Huevos enteros:** Hoy los cuenta en las comidas del día, sin claras y a
  55 g por huevo si se anotaron por peso. Avisa desde 5.
- **Hidratación del partido:** el formulario de fútbol pide el peso antes y
  después y lo bebido. Con eso calcula la tasa de sudor y cuánto reponer
  (1,5 L por kg perdido).
- **Regla de las 2 semanas** (Cuerpo): compara el promedio semanal en ayunas
  con el de 2 semanas antes.

  | Bajada | Qué hacer |
  |---|---|
  | Más de 0,7 kg/sem | +150–200 kcal |
  | 0,4–0,6 kg/sem | No cambiar |
  | Menos de 0,25 kg/sem y el abdomen quieto 3 semanas | −150 kcal o +2.000 pasos |

  Sin pesajes recientes, pide pesarse.

## Retomar Cindy y Tabata (1.17.0)

Cindy y Tabata guardan una foto (`TimerSnapshot`, marcas de reloj) en cada
cambio. Si Android cierra la app, Hoy ofrece retomarlos donde iban; si el
AMRAP terminó con la app cerrada, pide la ronda a medias. Cortados antes de
tiempo quedan incompletos (desde la 1.16.0).

## Registro de la mañana, carga y recuperación (1.19.0, §16.15, §19.6)

[`recovery.dart`](../lib/domain/recovery.dart) y
[`morning_check_screen.dart`](../lib/features/home/morning_check_screen.dart).

- **Registro de la mañana**: peso en ayunas, pulso en reposo al despertar,
  horas en cama y molestias por zona (0–10). Hoy lo propone hasta las 2 p. m.
  y está en Registrar.
- **Peso con momento**: en ayunas, antes de dormir, antes o después del
  fútbol, u otro. Solo en ayunas entra en el promedio semanal. El fútbol trae
  solos los pesajes de antes y después.
- **Pulso en reposo**: si 3 días seguidos está 5 lpm o más por encima de la
  media de los 7 anteriores, Hoy sugiere la versión ligera.
- **Molestias**: si una zona no baja en 3 días o sube, Hoy pide aplazar
  piernas o el intento de récord.
- **Carga** (RPE × minutos, también el fútbol). Hay tres casos que la hacen
  alta: dos sesiones hoy, ≥ 600 en el día, o 3 días intensos seguidos.
  - Con el día hecho, Hoy dice **"Día completo"** y recomienda recuperación
    de piernas, hidratación y sueño.
  - "Otra sesión" queda como enlace y, con carga alta, pide confirmación.
- **Plan B (solo torso)**: con 3 días intensos o molestia en la pierna, el
  día que trae pierna propone supinas, flexiones, pike, remo, plancha lateral
  y hollow, a RIR 2.
- **Recuperación de piernas** (§19.9): rutina guiada de 10–12 min, como la
  movilidad nocturna.
- **Pasos**:
  - con sesión o partido hoy, el aviso de sincronizar el reloj salta a la
    hora;
  - los pasos a mano (Registrar → Pasos) solo se reemplazan si Health
    Connect trae más.
- **Huevos**: cuentan los del nombre ("4 huevos + queso") y los huevos por
  porción de cada alimento (se editan en el catálogo).
- **Datos del 5 oct**: tres pesajes de referencia y 8.514 pasos, como
  correcciones del traspaso.

## Planche y habilidades (1.19.0, §19.7, §19.8)

- **Interruptor "Tengo las mini paralelas"** en Plan semanal. Martes, jueves
  y viernes del v3.1 empiezan con:
  - muñecas;
  - inclinación de planche;
  - flexiones pseudo-planche, solo el martes;
  - tuck planche, cuando la última inclinación llegó a 3 × 30 s.

  En descarga, solo inclinaciones. El bloque se arma igual al empezar y al
  retomar, para que el guion no cambie.
- **Habilidades** (Cuerpo): las 14 de la hoja de ruta, con criterio, ventana
  estimada desde oct 2026 y prerrequisitos. Se marcan a mano con la fecha.

## Escaleras de core (1.21.0, §19.10)

- [`core_ladders.dart`](../lib/domain/core_ladders.dart): **dragon flag** el
  lunes (6 peldaños, desde el encogimiento inverso) y **V-up** el jueves (4,
  desde el tuck-up). Las dos empiezan en el peldaño 1 el lunes del v3.1.
- `TrainingRepository.withLadder` mete el peldaño actual en el bloque
  `escalera`, antes de lo opcional; el peldaño 1 lleva el hollow del criterio
  (3 × 40 s el lunes, 3 × 30 s el jueves). En descarga, 2 series. Hoy y empezar usan `withV31Blocks` (planche + escalera). Retomar usa el día
  efectivo congelado en el snapshot; una bajada o edición no cambia esa sesión.
- Subir: el criterio en **2 sesiones seguidas** y **14 días** en el peldaño.
  Hoy y Cuerpo lo proponen; sube el usuario. Lo importado no cuenta.
- **Molestia lumbar**: chip en el descanso de una serie de la escalera (y en
  Cuerpo → Escaleras). Baja un peldaño, reinicia los 14 días y esa sesión no
  cuenta como limpia. El evento persiste por identidad de sesión para no duplicar
  bajadas al reabrir. Cada cambio abre una época nueva: una guía vieja guardada
  después no cuenta para el peldaño nuevo. El consejo se actualiza al crear, editar
  o borrar series; la subida revalida el criterio dentro de una transacción.
- Cuerpo → Escaleras permite elegir el peldaño a mano (p. ej. tras el test).

## Test de condición (1.21.0, §19.11)

- [`fitness_test.dart`](../lib/domain/fitness_test.dart): 12 pruebas de
  torso, core y habilidades y 4 de piernas.
- Calendario (`scheduledTest`):
  - Test 1: lunes de la semana 1 (torso, **sustituye el tirón**) y miércoles
    (piernas, después del FIFA 11+ y antes de la sesión);
  - Test 2: lunes y miércoles de la descarga (semana 6, 16 y 18 nov);
  - Test 3: miércoles de la semana 9 (piernas) y el viernes de pruebas
    (torso, 11 dic).
- Hoy y Cuerpo → Test permiten abrir, continuar y editar conservando la fecha
  original. **Modo test**: campo y calidad por lado, descanso de 3 min. Vacío
  queda pendiente, 0 es un intento válido. Completo requiere todos los ítems y
  ambos lados; guardar parcial mantiene acceso. Una sesión `otro`/`test` cuenta
  como actividad para la racha, pero sólo torso **completo en lunes** sustituye
  tirón. Piernas deja su sesión pendiente; el Test 3 de torso no sustituye Cindy.
  El tiempo de esta pantalla no mide esfuerzo: duración 0, sin estimación de kcal.
  Los resultados/lados/calidad se incluyen en el contexto del informe.
- Por lado cuenta el más débil sólo si se midieron I y D; parcial no produce
  mejora ni dosis bilateral. Tu progreso y Cuerpo → Test muestran
  T1 / T2 / T3 con el % de mejora contra el Test 1 y la dosis inicial:
  - reps, el tope del rango al 70–75 % del máximo;
  - aguantes, series del 50–60 %.
  La dosis se muestra; el plan no se reescribe solo.

## Pendiente

- Figuras 3D del resto de los ejercicios. Ya están el pino, el nórdico y las
  dominadas con mochila.
- Récord propio de Cindy y su gráfica.
- Ilustraciones de los peldaños 2+ de las escaleras (el handoff las deja para
  cuando el usuario llegue).
- Pulso en reposo desde Health Connect (`RestingHeartRateRecord`); hoy se
  anota a mano.
