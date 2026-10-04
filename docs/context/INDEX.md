# Índice de contexto

Punto de entrada antes de tocar el repositorio. Cada documento tiene un dueño
de tema; si un hecho cambia, se actualiza aquí y en su documento.

| Tema | Documento | Cuándo se actualiza |
|---|---|---|
| Qué es y cómo se corre | [../../README.md](../../README.md) | Cambian comandos, stack o estructura |
| Alcance, riesgos y gates | [../project-map.md](../project-map.md) | Cambia el alcance o aparece un riesgo nuevo |
| Registro de comidas | [../comidas.md](../comidas.md) | Cambia cómo se registra, un combo o las franjas |
| Diseño y motivación | [../diseno.md](../diseno.md) | Cambia la paleta, un anillo, una gráfica o las fotos |
| Notificaciones | [../notificaciones.md](../notificaciones.md) | Cambia un aviso, su hora o el permiso |
| Cronómetro guiado | [../cronometro.md](../cronometro.md) | Cambia cómo se recorre la sesión o los descansos |
| Plan v3 "Cierre de año" | [../plan-v3.md](../plan-v3.md) | Cambia la semana tipo, la periodización o un cronómetro del v3 |
| Datos e invariantes | [../modelo-datos.md](../modelo-datos.md) | Cambia una tabla, una unidad o el esquema |
| Producto del informe | [../informe.md](../informe.md) | Cambia una sección, una métrica o una alerta |
| Desviaciones de la planeación | [../auditoria-planeacion.md](../auditoria-planeacion.md) | Se acepta o rechaza un cambio al plan original |
| Traspaso v2: qué se hizo con cada punto | [../handoff-v2-2026-09-25.md](../handoff-v2-2026-09-25.md) | Se cierra un pendiente del traspaso |
| Auditoría técnica y plan de mejora | [../auditoria-2026-09-23.md](../auditoria-2026-09-23.md) | Se cierra un hallazgo o una fase del plan |
| Respaldo, restauración y releases | [../actualizaciones.md](../actualizaciones.md) | Cambia el flujo de respaldo, la firma o el pipeline |
| Decisiones durables | [../adr/](../adr/) | Se toma una decisión difícil de revertir |
| Fases y pendientes | [../roadmap.md](../roadmap.md) | Entra o sale trabajo del MVP/v2 |

## Hechos que no se deducen del código

- La fecha de inicio del programa (la que el usuario fija en Perfil) ancla las
  semanas del informe, que van de **lunes a domingo** como el plan y el fútbol
  (§16.8, desde la 1.13.0): la semana 1 empieza el lunes de la semana del
  inicio (con inicio el mié 26 ago, el lun 24 ago). Antes iban de miércoles a
  martes.
- El informe se pega en un chat para que un tercero lo audite. Por eso incluye
  detalle crudo (vueltas, series partidas, contexto) y no solo promedios.
- Los datos viven únicamente en el dispositivo. No hay backend ni sincronización.
  Respaldo: exportar a mano desde Ajustes (lo único que protege de perder el
  teléfono) y una copia automática semanal dentro de la app (protege de
  errores). Ambas se restauran desde Ajustes. Las fotos no van en ninguna.
- Fuera de la base viven `flags.json` (permisos ya pedidos, fechas de copia) y
  `sesion-en-curso.json` (cronómetro a medias). Restaurar no los toca.
- En este equipo, desde el 2 oct 2026 `C:lutter` es Flutter 3.47 (lo
  actualizó otro proyecto); el 3.22 de este repo está en
  `C:lutter-3.22-oldin`. Con 3.47 el análisis falla (`CardTheme`) y `pub`
  reescribe `pubspec.lock`: anteponer esa ruta al `PATH` antes de compilar.
- Flutter está fijado en 3.22: `pub` resuelve versiones de `fl_chart` y
  `share_plus` que luego no compilan. Compilar el APK y correr las pruebas de
  pantalla es la verificación real de cualquier cambio de dependencias.
- Las versiones se publican como GitHub Releases públicas y **todas deben ir
  firmadas con la misma llave**, o Android no deja actualizar sobre lo instalado.
  Esa llave es la **debug del equipo de desarrollo**, subida como secret el 24
  sep 2026; desde la 1.6.1 CI firma y publica (huella verificada). Ver "La llave de las releases" en
  [actualizaciones.md](../actualizaciones.md).
- Las metas (proteína, kcal, piso de alerta, calentamiento mínimo, ventana de
  medición) viven en la tabla `profiles` y se pueden editar en Ajustes.
- El catálogo de alimentos y los combos se siembran en la primera apertura
  (`lib/data/seed_foods.dart`). Cada alimento dice si sus macros salen de una
  etiqueta o de una tabla de referencia, y el informe reporta esa proporción.
- El plan que se siembra en la primera apertura está en `lib/data/seed_plan.dart`
  (dos versiones: base y la que añade bloques de core, cuádriceps y hombro).
  Editarlo desde la app crea versiones nuevas; la siembra no vuelve a correr.
- Pasos: la app del reloj (Innova S-Watch, *Yo → Health Connect*) los escribe
  en Health Connect y esta app los trae al abrirse si se conectó en Ajustes
  ([ADR 0007](../adr/0007-pasos-por-health-connect-nativo.md)). También se
  anotan a mano; se queda la cifra mayor. La meta (7.500) es solo entre
  semana.
- El emulador se prueba con APK debug, que no recorta recursos: lo que toque
  avisos o recursos pedidos por nombre se verifica **con un APK release**
  (de la 1.8.0 a la 1.9.0 los avisos no salían por eso; ver
  notificaciones.md).
- Las figuras de técnica se generan con `python tool/figuras.py` (fuente
  única) en `assets/tecnica/figuras.json`; no se editan a mano.
- Las entradas libres se guardan solas en el catálogo (`origin =
  entradaLibre`). Un alimento "a ojo" sigue contando como estimado en el
  informe aunque ya esté en el catálogo.
- El informe de ejemplo (`docs/ejemplo-informe.md`) no se versiona: se genera en
  local con `dart run tool/sample_report.dart`.

## Glosario

- **Trabajo neto**: total − calentamiento − enfriamiento − descansos.
- **Tiempo de circuito**: total − calentamiento − enfriamiento (con descansos);
  sobre él se miden las vueltas.
- **Trabajo por ronda**: de que arranca la ronda a su última repetición, sin
  el descanso previo. **R1→Rn**: trabajo de la última menos el de la primera
  (degradación).
- **Día cerrado**: con desayuno, almuerzo y cena, con 3 comidas o 1.800 kcal
  registradas (regla alternativa, §16.6.3), o cerrado a mano. Solo esos
  entran a promedios y alertas de nutrición.
- **Movilidad**: sesión opcional fuera del plan. No cuenta para adherencia,
  racha, récords ni RPE; el informe la muestra aparte.
- **Día entrenado**: para la racha, un día con una sesión que no sea de
  movilidad o con un partido. En Hoy, el ✓ del día pide la sesión del plan;
  un partido solo lo cumple en días de fútbol o descanso.
- **Ronda**: vuelta completa al circuito. **Vuelta/marca**: tiempo de una ronda
  registrado con el contador.
- **Serie partida**: serie que no se completó de corrido (12+3).
- **Toma de medidas (check-in)**: todas las medidas de una misma fecha.
- **Versión del plan**: foto inmutable del plan semanal vigente desde una fecha.
