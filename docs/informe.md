# El informe

Producto principal: Markdown por rango de fechas (por defecto, una semana
anclada a la fecha de inicio). Se copia o se comparte desde la pestaña
*Informe*.

Generador: [`lib/domain/report/report_builder.dart`](../lib/domain/report/report_builder.dart)
(función pura). Datos de entrada: `ReportInput`, armado por
[`report_repository.dart`](../lib/data/repositories/report_repository.dart).
Pruebas: [`test/domain/report_test.dart`](../test/domain/report_test.dart).

Para ver una salida completa con datos de ejemplo:
`dart run tool/sample_report.dart > docs/ejemplo-informe.md` (no se versiona).

## Secciones

1. **Encabezado** — rango, número de semana desde el inicio y versión(es) del
   plan vigentes en el rango (`Plan v1 (desde 26 ago) → v2 (desde 20 sep)`).
2. **Resumen** — sesiones hechas/planificadas (con cuántas quedan por delante
   si el rango no ha terminado: `1/3 (quedan 2 en el plan)`), fútbol, récord de rondas frente
   al anterior, proteína y kcal promedio (solo días registrados), días bajo el
   piso, peso promedio y Δ contra la línea base.
3. **Sesiones** — tabla (día, tipo, total, cal/enf, neto, rondas, RPE, series
   partidas, contexto) y detalle por sesión con vueltas, series y notas. La
   celda de rondas dice hechas sobre planificadas (`7/8 (incompleta)`) y el
   tipo se marca `⚠ fuera de plan` cuando no era lo que tocaba.
4. **Fútbol** — tabla aparte; el fútbol no es una sesión de circuito.
5. **Nutrición** — kcal y proteína por comida y día, promedio de macros y
   detalle de qué se comió.
6. **Medidas** — solo si hubo toma en el rango: línea base, actual y Δ, en la
   unidad elegida.
7. **Alertas automáticas** — abajo.
8. **Notas de la semana** — texto libre editable en la app.

La sección de nutrición cierra con la **procedencia de las kcal**: qué parte
viene de etiquetas verificadas, qué parte de tablas de referencia y qué parte
son entradas libres estimadas a ojo. Sirve para saber cuánta confianza merece
un promedio antes de tomar una decisión con él.

## Reglas de cálculo

- **Semana N** = `floor((fecha − inicio) / 7) + 1`; la semana va del inicio +
  (N−1)·7 días a +6. No es semana calendario.
- **Circuito neto** = total − calentamiento − enfriamiento (mínimo 0).
- **Sesiones esperadas** = días del rango cuyo tipo, según la versión del plan
  vigente *ese día*, es circuito o bloques. El fútbol se cuenta aparte. La
  alerta de "por debajo del plan" solo mira los **días ya cerrados** (antes de
  hoy): a mitad de semana, hoy y lo que falta no son faltas.
- **Promedios de nutrición**: solo sobre días con al menos una comida
  registrada. Un día sin registro no cuenta como día de 0 kcal; se lista como
  alerta para que el promedio no engañe.
- **Récord de rondas**: máximo de rondas **contadas** de sesiones de circuito
  dentro del rango, comparado con el máximo anterior al rango. Las rondas
  estimadas por tiempo no cuentan como marca; las de una sesión cerrada antes
  de tiempo sí.
- **Rondas estimadas**: se marcan con `~` y `(est.)`, y generan alerta.
- **Regla de progresión**: solo se sube de ronda con 0 series partidas, sin
  fallo, técnica buena, rango completo y recuperación normal. La sesión guarda
  esas tres condiciones; el informe compara cada sesión de circuito con la
  anterior **del mismo tipo** (circuito, circuito ligero y progresión llevan
  cuentas separadas).

## Alertas

Implementadas en [`alerts.dart`](../lib/domain/report/alerts.dart). Cada regla
es independiente; los umbrales viven en el perfil salvo el mínimo de
enfriamiento, que es una definición y no una meta.

| Alerta | Condición | Umbral |
|---|---|---|
| Sin registro de comidas | Días del rango ya transcurridos sin ninguna comida | — |
| Días seguidos bajo el piso | Racha ≥ 2 días registrados bajo el piso de kcal | `kcalFloor` (2.000) |
| Proteína baja | Promedio del rango bajo el mínimo | `proteinMin` (130 g) |
| Sesiones por debajo del plan | Hechas < esperadas en días ya cerrados | Plan vigente |
| Ejercicio partido repetido | Mismo ejercicio con serie partida en ≥ 3 sesiones | — |
| Progresión indebida | Se subió de ronda respecto a la sesión previa del mismo tipo con series partidas, fallo, técnica, rango o recuperación en rojo | Regla del plan |
| Calentamiento corto | Sesiones con calentamiento bajo el mínimo | `minWarmupSec` (6 min) |
| Enfriamiento corto | Sesiones con enfriamiento bajo el mínimo | 1 min, fijo en el código (`Targets.minCooldownSec`): por debajo no es enfriar. La meta de 3 min sí es del perfil |
| Fuera de plan | Se registró un tipo distinto al que pedía el día | Plan vigente |
| Sesión incompleta | Se cerró antes de completar el plan | — |
| Rondas estimadas | Sesiones con rondas calculadas por tiempo | — |
| Medición antes de tiempo | Toma a menos días de la anterior que el intervalo | `measureIntervalDays` (21) |
| Medidas sin ayunas | Alguna toma del rango marcada sin ayunas | — |

La app también avisa **antes** de guardar una medición prematura, con la opción
de guardarla igual.

## Qué no hace

- No interpreta ni recomienda: el análisis se hace fuera, con el informe pegado
  en el chat.
- No incluye fotos: son para mirarlas en el teléfono. Si algún día hacen falta,
  el informe diría qué tomas hay en el rango (fecha y ángulo), no las imágenes.
