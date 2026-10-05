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
    fútbol, proteína 160–170 g;
  - fija la próxima medición en el sábado de la semana 1.
- Un v3 activado para el mismo lunes queda reemplazado, porque a igual fecha
  gana la versión más nueva. La semana del bloque cuenta desde la primera
  versión v3.1.

## Semana tipo (§19.1)

| Día | Tipo | Qué |
|---|---|---|
| Lunes | Tren superior | Pino 5 min, dominadas con mochila, remo + laterales en superserie, pike, face pull, elevaciones colgado, rollout. Después, caminata de 15–20 min |
| Martes | Tren superior | Pino, fondos con mochila, arquero, flexiones con pies elevados, tríceps + curl en superserie, colgarse de la barra |
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

## Pendiente

- Figuras de los ejercicios nuevos. Hay un mockup 3D (maniquí con volumen,
  animado y que se gira) a la espera de que el usuario elija.
- Récord propio de Cindy y su gráfica.
- Retomar Cindy o Tabata si Android cierra la app a mitad.
- Una pantalla propia para las pruebas del 11 dic.
- Los ejercicios unilaterales siguen registrándose por lado como entradas
  sueltas (§16.6.2).
