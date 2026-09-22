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
| Decisiones durables | [../adr/](../adr/) | Se toma una decisión difícil de revertir |
| Fases y pendientes | [../roadmap.md](../roadmap.md) | Entra o sale trabajo del MVP/v2 |

## Hechos que no se deducen del código

- La fecha de inicio del programa (26 ago 2026) ancla las semanas del informe.
  No es la semana calendario: la semana N va del inicio + (N−1)·7 días a +6.
- El informe se pega en un chat para que un tercero lo audite. Por eso incluye
  detalle crudo (vueltas, series partidas, contexto) y no solo promedios.
- Los datos viven únicamente en el dispositivo. No hay backend ni sincronización;
  el único respaldo es exportar la base desde Ajustes.
- Metas vigentes: proteína 130–160 g/día, ~2.400 kcal, piso de alerta 2.000 kcal.
  Están en el perfil, no en el código.

## Glosario

- **Circuito neto**: total − calentamiento − enfriamiento.
- **Ronda**: vuelta completa al circuito. **Vuelta/marca**: tiempo de una ronda
  registrado con el contador.
- **Serie partida**: serie que no se completó de corrido (12+3).
- **Toma de medidas (check-in)**: todas las medidas de una misma fecha.
- **Versión del plan**: foto inmutable del plan semanal vigente desde una fecha.
