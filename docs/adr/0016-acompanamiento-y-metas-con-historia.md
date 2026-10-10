# 0016 — Acompañamiento con metas con historia (plan 009)

Fecha: 2026-10-10. Estado: aceptada para `claude/009-acompanamiento` (desde
`929f289`, candidata 1.22.0+30). Esquema **22** reservado para 009; el 21 es de
010 (catálogo). Decisión del owner (9 oct, en Codex): **«Base de 5.000;
revisar aumentos según progreso y recuperación»**. Sin promedio semanal 7.500.

## Contexto

La app aplicaba la meta actual del perfil a todo el pasado: cambiar 7.500 →
5.000 reclasificaba días viejos. Los consejos estaban dispersos y no tenían
vigencia, decisión ni revisión; Hoy pedía caminatas aunque se hubiera
declarado agotamiento.

## Decisión

- **Metas con vigencia** (`goal_versions`): pasos, proteína mín/máx, kcal y
  kcal de fútbol. Cada día se evalúa con la que regía. La migración 22 copia
  el perfil como **legado**: una fila sin fecha (el pasado sigue incierto:
  "meta histórica no registrada", no se clasifica) y el mismo valor conocido
  **desde el día de la migración**, para que tras 2 semanas se pueda revisar
  (revisión de Codex). Una instalación nueva arranca conocida desde hoy.
- **El perfil es una proyección**: aceptar con vigencia futura no lo escribe
  hoy; `projectDueGoals` lo actualiza cuando la vigencia llega (Hoy y avisos
  lo llaman antes de leer). Idempotente, sin crear vigencias.
- **Referencias del radar** (plan 011): seis `GoalMetric` opcionales
  (`refDominadas`, `refFlexiones`, `refHollow`, `refBulgara`,
  `refSaltoLargo`, `refCindy`), sin defaults ni proyección al perfil; null =
  sin referencia; `setReference` con aceptación explícita y vigencia.
- **Una sola puerta**: `GoalRepository.updateProfile` (Ajustes, activación del
  v3.1, siembra, corrección `metas-v31`). Guardar sin cambios no crea filas.
- **Lectura del día** (`stepsReading`, puro y reproducible; política v1):

  | Señal | Lectura |
  |---|---|
  | Racha intensa (existente, ≥ 3 días) o cansancio declarado (RPE ≥ 9 hoy o ayer, o "cansado" al despertar) | **Recuperar**: pasos suaves, sin caminata extra; el aviso de pasos no sale |
  | < 8 de los últimos 10 días entre semana con pasos | **Faltan datos** |
  | Meta cambiada por la persona hace < 14 días | **En prueba**, revisión a los 14 días |
  | ≥ 80 % de los días juzgables en la meta y promedio redondeado (500, hacia abajo) mayor que la meta | **Propuesta** de subir a ese promedio, si además: |
  | … carga alta hoy (≥ 600) o dos sesiones hoy | **Observando**: la revisión espera |
  | … ninguna señal favorable conocida en 3 días (al despertar 1–2 o RPE ≤ 8) | **Faltan datos**: no se presume recuperación |
  | Cambio en prueba ya revisado con < 50 % de cumplimiento | **Revisar** (volver atrás lo decide la persona) |
  | Lo demás | **Observando** |

- **Propuestas** (`coach_proposals`): ID estable `pasos:A>B:p1`. Aceptar
  (con cifra editable) rige **desde mañana**, idempotente; posponer = 7 días;
  rechazar vale para su ventana: se reconsidera sólo con una ventana nueva
  completa (14 días después) u otra cifra; no se repite cada mañana.
- Hoy y el aviso de pasos leen la **misma** lectura (`CoachRepository`).
  "Sin responder" no es descanso ni fatiga.

## Fuentes de los números

- 14 días / 2 semanas: la regla de las 2 semanas y las escaleras de core
  (14 días en el peldaño).
- Racha intensa ≥ 3 y RPE ≥ 7 como intenso: `recovery.dart` existente.
- Carga alta 600 y dos sesiones hoy: `recovery.dart` existente.
- **Nuevos, política v1 a confirmar por el owner**: cobertura 8/10, 80 %
  para proponer, 50 % para revisar, RPE ≥ 9 como cansancio, RPE ≤ 8 o
  despertar 1–2 como señal favorable, ventana de 3 días, redondeo de 500.
  No suben nada solos: la cifra sugerida es el promedio propio.

## Fuera de este tramo

- Propuestas de fuerza, rondas y escaleras dentro de la misma lectura: esperan
  la evidencia de 008 (`StrengthSessionEvidence` con `mode`) de la
  integración 122.
- Cobertura de 1.000 días y conteo de consultas (paso 5 del plan).
- Metas de kcal/proteína con propuestas: hoy sólo se versionan y el informe
  mide la proteína de cada día con la suya.
