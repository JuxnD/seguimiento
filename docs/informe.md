# El informe

Producto principal: Markdown por rango de fechas (por defecto, una semana
anclada a la fecha de inicio). Se copia o se comparte desde la pestaña
*Informe*.

Generador: [`lib/domain/report/report_builder.dart`](../lib/domain/report/report_builder.dart)
(función pura). Datos de entrada: `ReportInput`, armado por
[`report_repository.dart`](../lib/data/repositories/report_repository.dart).
Pruebas: [`test/domain/report_test.dart`](../test/domain/report_test.dart).

Ejemplo de salida con datos ficticios: [ejemplo-informe.md](ejemplo-informe.md).

## Secciones

1. **Encabezado** — rango, número de semana desde el inicio y versión(es) del
   plan vigentes en el rango (`Plan v1 (desde 26 ago) → v2 (desde 20 sep)`).
2. **Resumen** — sesiones hechas/planificadas, fútbol, récord de rondas frente
   al anterior, proteína y kcal promedio (solo días registrados), días bajo el
   piso, peso promedio y Δ contra la línea base.
3. **Sesiones** — tabla (día, tipo, total, cal/enf, neto, rondas, RPE, series
   partidas, contexto) y detalle por sesión con vueltas, series y notas.
4. **Fútbol** — tabla aparte; el fútbol no es una sesión de circuito.
5. **Nutrición** — kcal y proteína por comida y día, promedio de macros y
   detalle de qué se comió.
6. **Medidas** — solo si hubo toma en el rango: línea base, actual y Δ, en la
   unidad elegida.
7. **Alertas automáticas** — abajo.
8. **Notas de la semana** — texto libre editable en la app.

## Reglas de cálculo

- **Semana N** = `floor((fecha − inicio) / 7) + 1`; la semana va del inicio +
  (N−1)·7 días a +6. No es semana calendario.
- **Circuito neto** = total − calentamiento − enfriamiento (mínimo 0).
- **Sesiones esperadas** = días del rango cuyo tipo, según la versión del plan
  vigente *ese día*, es circuito o bloques. El fútbol se cuenta aparte.
- **Promedios de nutrición**: solo sobre días con al menos una comida
  registrada. Un día sin registro no cuenta como día de 0 kcal; se lista como
  alerta para que el promedio no engañe.
- **Récord de rondas**: máximo de rondas de sesiones de circuito dentro del
  rango, comparado con el máximo anterior al rango.
- **Rondas estimadas**: se marcan con `~` y `(est.)`, y generan alerta.

## Alertas

Implementadas en [`alerts.dart`](../lib/domain/report/alerts.dart). Cada regla
es independiente; los umbrales viven en el perfil, no en el código.

| Alerta | Condición | Umbral |
|---|---|---|
| Sin registro de comidas | Días del rango ya transcurridos sin ninguna comida | — |
| Días seguidos bajo el piso | Racha ≥ 2 días registrados bajo el piso de kcal | `kcalFloor` (2.000) |
| Proteína baja | Promedio del rango bajo el mínimo | `proteinMin` (130 g) |
| Sesiones por debajo del plan | Hechas < esperadas | Plan vigente |
| Ejercicio partido repetido | Mismo ejercicio con serie partida en ≥ 2 sesiones | — |
| Calentamiento corto | Sesiones con calentamiento bajo el mínimo | `minWarmupSec` (6 min) |
| Rondas estimadas | Sesiones con rondas calculadas por tiempo | — |
| Medición antes de tiempo | Toma a menos días de la anterior que el intervalo | `measureIntervalDays` (21) |
| Medidas sin ayunas | Alguna toma del rango marcada sin ayunas | — |
| Sesión en día no planificado | Entrenaste un día marcado como descanso o fútbol | Plan vigente |

La app también avisa **antes** de guardar una medición prematura, con la opción
de guardarla igual.

## Qué no hace

- No interpreta ni recomienda: el análisis se hace fuera, con el informe pegado
  en el chat.
- No incluye fotos; cuando existan, las referenciará por fecha y ángulo.
