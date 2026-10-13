# 032 · Rutinas diarias y recuperación activa (12–13 oct 2026)

Estado: **IMPLEMENTADO EN LOCAL, con pruebas dirigidas en el host.** Falta la
revisión de Codex, la suite completa en la integración, Android y la
aceptación del owner. Sin push, APK ni teléfono.

- Base: `8ef2df4`.
- Rama: `JuxnD/032-recuperacion-readiness`.
- Worktree: `C:/My Projects/seguimiento-032-recuperacion`.
- Plan: `seguimiento-122-integracion/plans/032-recuperacion-readiness.md`.
- Especificación: handoff del 12 oct, §19.14, §19.15 y §19.17. Las pruebas
  usan fechas ficticias (marzo de 2030), sin historial del owner.

## Qué hace

- **`readiness()`** (`lib/domain/readiness.dart`) es pura y la usan Hoy, el
  aviso de las 22:00 y el informe. Los umbrales son los del traspaso:
  - **Rojo** (`restOnly`): rodilla en escaleras ≥ 5, pulso ≥ base + 10, o
    enfermo / fiebre / dolor agudo.
  - **Amarillo** (`recoveryActive`), con cualquiera de estas:
    - carga de los últimos 3 días ≥ 900;
    - 2 partidos entre ayer y hoy;
    - relación aguda:crónica > 1,5 (sólo con ≥ 21 días de historial);
    - esfuerzo ≥ 8 ayer y sueño < 7 h;
    - pulso ≥ base + 5;
    - escaleras 3–4;
    - dolor muscular ≥ 6;
    - sueño < 6 h.
  - **Verde** si no se cumple ninguna.
- Los datos que faltan van a `missing` («Pulso: sin dato»). Un verde con
  huecos se titula «el plan normal, con datos incompletos» y nunca afirma que
  estás recuperado.
- **Rutinas** (`lib/domain/daily_routines.dart`):
  - Mañana · Activa: 10 ejercicios, con una versión de 4 min.
  - Noche · Suelta: 8 ejercicios, más el módulo de piernas los días de fútbol
    o de piernas. La noche de partido, pike y pancake van al 4/10 y sin
    pulsos.
  - Recuperación activa: bloque A (Activa), bloque B (activación, 2 vueltas
    con 45 s entre ellas) y bloque C (Suelta con piernas). Dura unos 30 min;
    la caminata opcional va fuera del cronómetro.
  - Cada ejercicio tiene `id`, `purpose` y claves de técnica del Anexo B.
- **Guardado**:
  - Todas se guardan como `movilidad` con su id en `sessions.mode`.
  - La recuperación pide el RPE al cerrar. Si pasa de 5, ofrece guardarla
    como sesión normal (`otro`).
  - Al terminar, pregunta «¿Algo tirante o con molestia?» y lo anota en
    `soreness_logs`, conservando el valor más alto del día.
- **Efectos**:
  - Activa y Suelta no suman carga ni la cadena intensa, y no tocan la racha
    🔥; llevan una racha de movilidad propia.
  - La recuperación activa tampoco suma carga ni cadena, pero sí mantiene la
    racha 🔥.
- **Hoy**:
  - En días amarillos o rojos, una tarjeta reemplaza a la sesión. Tiene
    «Empezar recuperación» (en rojo, «Movilidad suave (Suelta)», sin el
    bloque B) y «Entrenar igual», que pide confirmación citando la carga.
  - Si hoy hay test, aparece «Mover test a mañana».
  - Tarjeta «Rutinas del día» con «Mañana ✓», «Noche ✓» y la racha de
    movilidad.
  - El registro de la mañana suma dolor muscular (0–10) y «enfermo, con
    fiebre o con dolor agudo».
- **Decisiones** (`coach_proposals`, sin columnas nuevas):
  - «Entrenar igual» se guarda como `recuperacion:<día>`, estado
    `rechazada`, con nivel, razones y faltantes en `evidence` y la fecha de
    la decisión.
  - La aceptación es la sesión `recovery_active` guardada; abrir la rutina no
    cuenta.
- **Tests movidos**:
  - Id `mover_test:<inicio v3.1>:<ronda>:<parte>:<n>`, con la identidad y el
    origen en `evidence`.
  - Máximo 2 movimientos por test y por plan.
  - Sólo se mueve desde el día que le toca ahora: una fecha arbitraria o un
    `from` repetido lanzan `ArgumentError`.
  - `effectiveScheduledTest(start, date)` es el contrato que reutilizará 034;
    el dashboard ya lo usa para el test de hoy y la víspera.
- **Avisos**: tres `ReminderKind` al final del enum, para no mover los ids de
  notificación:
  - `recuperacionManana`, a las 22:00, si la carga de ayer y hoy ≥ 900;
  - `rutinaManana`, a las 7:15;
  - `rutinaNoche`, a las 21:30.

  Las rutinas no suenan si ya se hicieron hoy. Las horas son fijas y
  editables.
- **Informe**: sección «Recuperación» sólo en el informe semanal (≤ 14 días):
  - propuestos · aceptados · entrenó igual;
  - carga máxima de 3 días y relación aguda:crónica;
  - una línea por cada día amarillo o rojo, con sus razones.
- **Esquema 24**: `morning_checks.muscle_soreness` (0–10) e `ill`, nullable y
  sin backfill. Detalle en `docs/modelo-datos.md`.

## Límites declarados

- **Ventanas**: van por día de calendario. «Últimos 3 días» es D-2..D y «hoy y
  ayer» es D-1..D. No son 48 ni 36 h exactas, porque `football_games` no
  guarda hora.
- **Pulso**: sólo el manual de la mañana; la base son las 14 lecturas previas
  más recientes, con un mínimo de 7. El pulso nocturno de Health Connect y la
  hora de despertar del reloj quedan para el frente D.
- **Escaleras**: salen de la molestia `Rodilla` del día. Un 0 no se guarda,
  así que sin fila es «sin dato», nunca 0. El campo propio llega con 034.
- **Rojo frente a §19.16**: el rojo es `restOnly`. El texto cita los
  isométricos de rodilla del traspaso, pero no hay rutina isométrica (es de
  034); el único botón es Suelta. No es una recomendación clínica: los
  umbrales son reglas de entrenamiento del traspaso.
- **Intento**: «test o intento» sólo considera el test del v3.1; el intento de
  récord no se detecta todavía.
- **Choque de tests**: si un test movido cae el mismo día que otro test
  planificado, gana el planificado.
- **Figuras**: 17 ejercicios nuevos no tienen figura y muestran «todavía no
  tiene una ilustración». La lista exacta está en manos de 035; 032 no edita
  assets.
- **Comida en día amarillo**: es sólo un texto orientativo; no cambia
  `goal_versions`.

## Evidencia (`032-evidence/`)

| Log | Qué | Resultado |
|---|---|---|
| 01 | `flutter pub get` | exit 0, `pubspec.lock` sin cambios |
| 02 | `build_runner build` | exit 0, 446 outputs |
| 03 | `flutter analyze --no-pub` | sin incidencias, exit 0 |
| 04 | `test/domain/readiness_test.dart` | 15/15 |
| 05 | `test/domain/daily_routines_test.dart` | 6/6 |
| 06a | `readiness_repository_test` (1.ª corrida) | 14/15: oráculo que comparaba un record con una List por identidad |
| 06 | ídem, oráculo corregido comparando el contenido | 15/15 |
| 07 | `test/data/migration_test.dart` | 20/20, con 23 → 24 y bases viejas → 24 |
| 08 | `test/data/schema21_122_integration_test.dart` | 1/1 |
| 09 | rojo por mutación: sin `recovery_active` en la racha | Expected 1, Actual 0, exit 1 |
| 10 | rojo por mutación: sin los `addColumn` v24 | `no such column: muscle_soreness`, exit 1 |

- Las mutaciones se revirtieron por copia de archivo y se verificaron.
  `git diff --check` está limpio.
- Las pruebas nuevas no compilan contra `8ef2df4`, porque las APIs no
  existían. Por eso el rojo útil de este recibo es el de mutación.
- **No corridas** y afectadas por el cambio: `reminders_test`,
  `restore_test`, `ladders_and_tests_data_test` y las pruebas de UI de Hoy.
  Van en la suite completa de la integración.
- Todo corrió con el SDK 3.22 (`C:/seguimiento-sdk-3.22.0`), `--concurrency 1`
  y `--timeout 90s`.

## R2: correcciones a la revisión R1 de Codex (13 oct)

- **P1, a medias no es hecho.** `recoveryDone`, `routinesOn` y
  `mobilityStreak` exigen `incomplete = false`. La racha 🔥 cuenta sólo la
  `recovery_active` terminada. Lo parcial queda registrado, pero no da ✓, no
  da «Día completo» y no silencia los avisos.
- **P2, refresco.** `dashboardProvider` observa `recoverySignalsProvider`
  (`soreness_logs`, `morning_checks`, `sleep_logs`). Una molestia anotada al
  cerrar la rutina llega a Hoy, al plan B y a las molestias persistentes sin
  otra acción.
- **P2, texto.** El diálogo de RPE > 5 explica qué guarda cada opción:
  «Sesión normal» suma carga y días intensos; «Recuperación» no suma carga y
  mantiene la racha.
- **Vista compartida.** `loadReadinessView()` es el cuerpo común de
  `readinessViewProvider`.

### Evidencia R2

| Log | Qué | Resultado |
|---|---|---|
| r2-red-01 / r2b-1 (diag75 = 75eeedb) | `readiness_partial_test` | 1/5. Rojos funcionales: a medias = hecha; provider real (la parcial se aceptaba); racha parcial 1; molestia sin llegar a Hoy. RPE > 5 pasa. |
| r2-red-03 / r2-red-04 (75) | `routine_reminders_test`, `restore_032_test` | 4/4 y 3/3: caracterización (respaldo 23 → 24 real; aviso desconocido da `RestoreException` y conserva la base). |
| r2-green-00, r2b-5 | `analyze` | sin incidencias |
| r2b-3 | `readiness_partial_test` | 5/5 |
| r2-green-02…08 | avisos, restauración, repositorio, `reminders_test`, `restore_test`, `ladders_and_tests_data_test`, `experience_test` | 4/4, 3/3, 15/15, 22/22, 8/8, 6/6, 5/5 |
| r2b-2 (75) | `readiness_home_test` | 1/4. «a medias» es rojo funcional. «mover test» pasa. «amarillo» y «rojo» dan timeout del arnés. |
| r2b-4 (WT032) | `readiness_home_test` | 1/4. «mover test» pasa. Las otras 3 dan timeout del arnés tras montar y desmontar, con las aserciones previas cumplidas. |

- Dos arnés anteriores de Hoy no cuentan como rojo ni como verde:
  - pintaba antes de que drift respondiera (r2-red-02, r2-probe);
  - `runAsync` se colgó y corté sólo mis procesos (r2-red-05, r2-green-09).
- El flutter_tester 61260 quedó huérfano porque no repasé el árbol completo.
  Lo cerró Codex con verificación. Ahora reconsulto todo el árbol antes de
  liberar.
- **Límite de la prueba de Hoy:** inyecta una vista precalculada y desmonta y
  vuelve a montar la pantalla. Prueba toques, decisiones y lo guardado, no la
  actualización reactiva de la misma pantalla.
- **Esa reactividad la prueba `readiness_partial_test`** con los providers
  reales:
  - `readinessViewProvider` se recalcula con un partido, con la recuperación a
    medias, con «Entrenar igual» y con la Activa terminada;
  - `dashboardProvider` se recalcula con una molestia.
- **Pendiente:** el arnés de Hoy rehecho con `drive()`, que avanza cuadros en
  la misma zona y falla tras un tope en vez de colgarse. Falta una ventana
  breve para correrlo.
