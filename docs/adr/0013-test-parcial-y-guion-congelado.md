# 0013 — Tests parciales y guion efectivo durable

Fecha: 2026-10-07. Estado: aceptada para la candidata local 1.21.0+29.

Los seis fallos reproducidos sobre afaaf86 mostraron que existencia de filas,
actividad del día y cumplimiento del plan tenían semánticas diferentes. El
test queda pendiente/parcial/completo según intentos presentes; sin omisión
implícita. Cero es medido; vacío no lo es. Torso completo lunes sustituye tirón,
piernas y torso del viernes no sustituyen su entrenamiento.

La pantalla de resultados no mide trabajo: sus sesiones registran duración0 y
la migración20 corrige la duración inferida de la candidata19. El descanso
visible sólo ayuda a realizar el test, sin fabricar calorías.

Los bloques de escalera son mutables entre sesiones. Se congela el día efectivo
en el snapshot, se persiste identidad de época en el registro de entrenamiento
y se identifica el incidente lumbar de forma idempotente. Una guía que comenzó
en una época anterior no acredita la nueva aunque se guarde después.

Se extienden los repositorios Drift, snapshots JSON y Riverpod existentes. No
se duplican el cronómetro, la BD ni el gateway. Los consejos observan todas sus
tablas fuente y la aceptación de subir revalida datos en transacción.

Evidencia: regresiones `release121_contracts_test.dart` y
`release121_flows_test.dart`; fixtures SQLite18/19 genuinas y comparación total
de columnas originales después de migrar, reabrir y exportar/restaurar ZIP.
