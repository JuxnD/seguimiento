# Índice de contexto

Punto de entrada antes de tocar el repositorio. Cada documento tiene un dueño
de tema; si un hecho cambia, se actualiza aquí y en su documento.

| Tema | Documento | Cuándo se actualiza |
|---|---|---|
| Qué es y cómo se corre | [../../README.md](../../README.md) | Cambian comandos, stack o estructura |
| Alcance, riesgos y gates | [../project-map.md](../project-map.md) | Cambia el alcance o aparece un riesgo nuevo |
| Datos e invariantes | [../modelo-datos.md](../modelo-datos.md) | Cambia una tabla, una unidad o el esquema |
| Producto del informe | [../informe.md](../informe.md) | Cambia una sección, una métrica o una alerta |
| Desviaciones de la planeación | [../auditoria-planeacion.md](../auditoria-planeacion.md) | Se acepta o rechaza un cambio al plan original |
| Respaldo, restauración y releases | [../actualizaciones.md](../actualizaciones.md) | Cambia el flujo de respaldo, la firma o el pipeline |
| Decisiones durables | [../adr/](../adr/) | Se toma una decisión difícil de revertir |
| Fases y pendientes | [../roadmap.md](../roadmap.md) | Entra o sale trabajo del MVP/v2 |

## Hechos que no se deducen del código

- La fecha de inicio del programa (la que el usuario fija en Perfil) ancla las
  semanas del informe. No es la semana calendario: la semana N va del inicio +
  (N−1)·7 días a +6.
- El informe se pega en un chat para que un tercero lo audite. Por eso incluye
  detalle crudo (vueltas, series partidas, contexto) y no solo promedios.
- Los datos viven únicamente en el dispositivo. No hay backend ni sincronización;
  el respaldo es exportar la base desde Ajustes y restaurarla desde ahí mismo.
- Las versiones se publican como GitHub Releases públicas y **todas deben ir
  firmadas con la misma llave**, o Android no deja actualizar sobre lo instalado.
- Las metas (proteína, kcal, piso de alerta, calentamiento mínimo, ventana de
  medición) viven en la tabla `profiles` y se pueden editar en Ajustes.
- El catálogo de alimentos y los combos se siembran en la primera apertura
  (`lib/data/seed_foods.dart`). Cada alimento dice si sus macros salen de una
  etiqueta o de una tabla de referencia, y el informe reporta esa proporción.
- El plan que se siembra en la primera apertura está en `lib/data/seed_plan.dart`
  (dos versiones: base y la que añade bloques de core, cuádriceps y hombro).
  Editarlo desde la app crea versiones nuevas; la siembra no vuelve a correr.
- El informe de ejemplo (`docs/ejemplo-informe.md`) no se versiona: se genera en
  local con `dart run tool/sample_report.dart`.

## Glosario

- **Circuito neto**: total − calentamiento − enfriamiento.
- **Ronda**: vuelta completa al circuito. **Vuelta/marca**: tiempo de una ronda
  registrado con el contador.
- **Serie partida**: serie que no se completó de corrido (12+3).
- **Toma de medidas (check-in)**: todas las medidas de una misma fecha.
- **Versión del plan**: foto inmutable del plan semanal vigente desde una fecha.
