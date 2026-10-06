# Índice de contexto

Punto de entrada antes de tocar el repositorio. Cada documento tiene un dueño
de tema; si un hecho cambia, se actualiza aquí y en su documento.

**Entrega vigente:** [1.19.0+27 publicada y verificada](sessions/2026-10-06-entrega-119.md).
Fuente ce68981, APK público y gateway comprobados. La captura del owner del
6 oct confirma uso del copiloto en el teléfono; versión instalada no inspeccionada.
Aceptación visual y proveedor externo de respaldos siguen pendientes.
**Candidato siguiente:** [asistente por tareas con revisión](../ia-oportunidades.md),
1.20.0+28 en `C:/My Projects/seguimiento-120-release`, rama `JuxnD/120-release`.
[Improve y alcance autorizado](../../plans/120-improve-audit.md),
[integración y gates](sessions/2026-10-06-integracion-120.md).
El candidato inicial de foto queda como [evidencia histórica](sessions/2026-10-06-candidato-120-ia.md).
No sustituye la release publicada.

| Tema | Documento | Cuándo se actualiza |
|---|---|---|
| Qué es y cómo se corre | [../../README.md](../../README.md) | Cambian comandos, stack o estructura |
| Alcance, riesgos y gates | [../project-map.md](../project-map.md) | Cambia el alcance o aparece un riesgo nuevo |
| Registro de comidas | [../comidas.md](../comidas.md) | Cambia cómo se registra, un combo o las franjas |
| Diseño y motivación | [../diseno.md](../diseno.md) | Cambia la paleta, un anillo, una gráfica o las fotos |
| Notificaciones | [../notificaciones.md](../notificaciones.md) | Cambia un aviso, su hora o el permiso |
| Cronómetro guiado | [../cronometro.md](../cronometro.md) | Cambia cómo se recorre la sesión o los descansos |
| Plan v3 "Cierre de año" | [../plan-v3.md](../plan-v3.md) | Cambia la semana tipo, la periodización o un cronómetro del v3 |
| Plan v3.1 (vigente desde el 12 oct) | [../plan-v3-1.md](../plan-v3-1.md) | Cambia la semana, el viernes, el RIR, la doble progresión, las metas por día o los hábitos (sueño, huevos, hidratación, regla de 2 semanas) |
| Datos e invariantes | [../modelo-datos.md](../modelo-datos.md) | Cambia una tabla, una unidad o el esquema |
| Producto del informe | [../informe.md](../informe.md) | Cambia una sección, una métrica o una alerta |
| Desviaciones de la planeación | [../auditoria-planeacion.md](../auditoria-planeacion.md) | Se acepta o rechaza un cambio al plan original |
| Traspaso v2: qué se hizo con cada punto | [../handoff-v2-2026-09-25.md](../handoff-v2-2026-09-25.md) | Se cierra un pendiente del traspaso |
| Auditoría técnica y plan de mejora | [../auditoria-2026-09-23.md](../auditoria-2026-09-23.md) | Se cierra un hallazgo o una fase del plan |
| Respaldo, restauración y releases | [../actualizaciones.md](../actualizaciones.md) | Cambia el flujo de respaldo, la firma o el pipeline |
| Decisiones durables | [../adr/](../adr/) | Se toma una decisión difícil de revertir |
| Fases y pendientes | [../roadmap.md](../roadmap.md) | Entra o sale trabajo del MVP/v2 |
| Copiloto semanal y activación | [../ia-pendiente.md](../ia-pendiente.md) | Cambia gateway, envío consentido, límites o aceptación |
| Preguntas con fuentes e historial local | [../ia-informes.md](../ia-informes.md) | Cambia snapshots, citas, límites, retención o acciones desde el informe/guía |
| IA en uso diario y comidas por foto | [../ia-oportunidades.md](../ia-oportunidades.md) | Cambia candidato, validación o prioridad de funciones |

## Hechos que no se deducen del código

- La fecha de inicio del programa (la que el usuario fija en Perfil) ancla las
  semanas del informe, que van de **lunes a domingo** como el plan y el fútbol
  (§16.8, desde la 1.13.0): la semana 1 empieza el lunes de la semana del
  inicio (con inicio el mié 26 ago, el lun 24 ago). Antes iban de miércoles a
  martes.
- El informe se pega en un chat para que un tercero lo audite. Por eso incluye
  detalle crudo (vueltas, series partidas, contexto) y no solo promedios.
- Registros y fotos viven en el dispositivo, sin sincronización. Desde 1.19,
  Ajustes exporta un ZIP portable con base y fotos. La copia semanal interna
  conserva solamente registros; ambas se restauran desde Ajustes. IA es opt-in:
  el texto exacto del informe o la guía seleccionada se envía tras confirmación;
  comparar el periodo previo requiere una elección explícita. Foto de comida y
  etiqueta tienen consentimiento separado: sólo sale la imagen elegida,
  reencodificada sin EXIF. Las fotos corporales no se incluyen en consultas.
- Fuera de la base viven `flags.json` (permisos ya pedidos, fechas de copia) y
  `sesion-en-curso.json` (cronómetro a medias). Restaurar no los toca.
- Flutter 3.22.0 / Dart 3.4.0 y Java 17 son los del pipeline. En este host se
  usa `C:/seguimiento-sdk-3.22.0/flutter/bin`, recuperado desde el archivo
  oficial con SHA-256 verificado. El SDK previo `C:/flutter-3.22-old` está
  incompleto y se preservó; su causa no se determinó. `C:/flutter` pertenece
  a otro proyecto (3.47); no usarlo ni cambiar dependencias/lock para esta app.
  [Recibo de integración](sessions/2026-10-06-integracion-120.md).
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
  semana. Innova escribe por lotes al sincronizar, con esa hora: Hoy muestra
  quién escribió el último registro y cuándo, y pide abrir la app del reloj
  si pasaron más de 6 h (§16.14).
- El emulador se prueba con APK debug, que no recorta recursos: lo que toque
  avisos o recursos pedidos por nombre se verifica **con un APK release**
  (de la 1.8.0 a la 1.9.0 los avisos no salían por eso; ver
  notificaciones.md).
- Las figuras de técnica se generan con `python tool/figuras.py` (fuente
  única) en `assets/tecnica/figuras.json`; no se editan a mano.
- El maniquí 3D (por ahora pino, nórdico y dominadas) sale de
  `python tool/figuras3d.py`, que importa `figuras.py`, en
  `assets/tecnica/figuras3d.json`. Se revisa a ojo con
  `FIG3D_OUT=<carpeta> flutter test test/ui/exercise_figure_3d_render_test.dart`
  (sin esa variable la captura se salta). Las pruebas usan fuentes versionadas,
  independientes del SDK del host. Ver [diseno.md](../diseno.md).
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
