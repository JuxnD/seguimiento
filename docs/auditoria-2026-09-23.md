# Auditoría técnica — 23 sep 2026

Revisión del estado real del repositorio (código, pruebas, CI, docs) con
hallazgos priorizados y un plan de mejora. Complementa, no reemplaza, a
[project-map.md](project-map.md) y [roadmap.md](roadmap.md).

## Estado verificado

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | Sin issues |
| `flutter test` | 133 pruebas verdes (los docs dicen 47) · 0 pruebas de widget |
| Versión | `pubspec` 1.5.0+8 · tags remotos v1.0.1 … v1.5.0 |
| Toolchain | Flutter 3.22.0 / Dart 3.4.0 (mayo 2024), fijado a propósito (ADR 0001) |
| Dependencias | 6 fijadas por debajo de lo resoluble; `sqlite3_flutter_libs` 0.5.x marcado EOL en pub; `build_runner` arrastra paquetes descontinuados |
| Cobertura | Dominio, repositorios, siembra, restauración y migraciones cubiertos. Sin pruebas: `chart_repository`, `dashboard_repository`, `photo_repository`, toda la UI |

Lo que está bien y conviene conservar: separación `domain` / `data` /
`features`; informe como función pura con pruebas; macros congelados;
versiones de plan inmutables; restauración validada con rollback; `lib/ui`
concentra tarjetas, campos y diálogos; los gaps async usan `mounted`; ADRs
con porqué; contexto durable en `docs/`.

Tres patrones explican la mayoría de los defectos: **«hoy» capturado una vez**
en objetos de larga vida (providers, pestañas del `IndexedStack`); **estado
local derivado de listas que cambian** sin reconciliar (dropdowns, campos sin
`key`, perfil en `late final`); y **escrituras sin manejo de errores**.

## Hallazgos

Severidad: **Alta** = pérdida de datos o función rota · **Media** = número
engañoso, comportamiento inconsistente o fricción contra la meta de 30 s ·
**Baja** = deuda o pulido.

### Alta

1. **Cronómetros sin persistencia** —
   [guided_session_screen.dart:85-100](../lib/features/training/guided_session_screen.dart#L85)
   y [round_counter_screen.dart:43-47](../lib/features/training/round_counter_screen.dart#L43).
   Todo el estado (`_startedAt`, `_index`, `_done`, `_roundMarks`) vive en el
   `State`. Si Android mata el proceso (llamada, cambio de app, memoria) se
   pierde la sesión completa. Es el riesgo abierto más viejo del roadmap.
   *Arreglo:* guardar un JSON con el estado en cada transición (archivo en el
   directorio de la app) y ofrecer «Reanudar sesión» en Entreno si existe.

2. **Alarma exacta en Android 14+** —
   [notification_service.dart:147](../lib/data/notification_service.dart#L147).
   `scheduleRestEnd` usa `exactAllowWhileIdle`. Con `targetSdk` 34,
   `SCHEDULE_EXACT_ALARM` no viene concedido: el plugin lanza
   `PlatformException(exact_alarms_not_permitted)`. La llamada va en
   `unawaited(...)` sin `catch`, así que el aviso de fin de descanso en
   segundo plano no suena y el fallo solo aparece en el log. No hay ninguna
   llamada a `canScheduleExactNotifications()` ni
   `requestExactAlarmsPermission()`.
   *Arreglo:* comprobar el permiso; si falta, pedirlo una vez desde Ajustes
   o caer a `inexactAllowWhileIdle`. Verificar en el teléfono (depende de la
   versión de Android).

3. **Copia previa al restore hecha con el archivo abierto** —
   [database_host.dart:43-49](../lib/data/database_host.dart#L43).
   `file.copy(safetyCopy)` copiaba el archivo con la conexión abierta. La base
   usa el modo de diario por defecto (DELETE, no WAL), así que lo ya
   confirmado está en el archivo; el riesgo real es menor del que se estimó al
   principio: una escritura en curso en ese instante. *Arreglo:* copia con
   `VACUUM INTO`, que la hace SQLite de forma consistente. (Severidad real:
   media; se deja aquí para no renumerar.)

4. **Restore fallido deja la app sobre una base cerrada** —
   [settings_screen.dart:131-132](../lib/features/settings/settings_screen.dart#L131).
   `DatabaseHost._rollback` reabre `_db`, pero `databaseGenerationProvider++`
   está después del `await` dentro del `try`: si `restoreFrom` lanza, nadie
   recrea repositorios ni streams y todo apunta a la conexión cerrada hasta
   reiniciar. *Arreglo:* incrementar la generación en `finally`, o que
   `DatabaseHost` exponga un `ValueNotifier` observado por el provider.

5. **Ajustes muestra el perfil viejo tras restaurar** —
   [settings_screen.dart:163](../lib/features/settings/settings_screen.dart#L163).
   `_ProfileCard` captura el perfil en `late final`; tras un restore el widget
   no se recrea, muestra los valores anteriores y «Guardar perfil» los
   escribiría encima de los restaurados. *Arreglo:* `key: ValueKey(generación)`
   o `didUpdateWidget`.

6. **Editor del plan guarda lo que no se ve** —
   [plan_edit_screen.dart:123-129](../lib/features/plan/plan_edit_screen.dart#L123).
   `_ExerciseRow` usa `TextFormField(initialValue:)` sin `key` en una lista
   mutable: al borrar el ejercicio *i*, Flutter reutiliza el `State` del campo
   en esa posición y muestra el texto del ejercicio borrado mientras el draft
   tiene otro valor. *Arreglo:* `key: ObjectKey(exercise)` en `_ExerciseRow` y
   `ObjectKey(day)` en `_DayCard`.

7. **Editar una toma y cambiar la fecha la duplica** —
   [measurement_form_screen.dart:80](../lib/features/body/measurement_form_screen.dart#L80).
   `saveCheckIn(_date)` borra e inserta en la fecha nueva; la toma original
   queda. Aparece dos veces en Cuerpo y en la gráfica. *Arreglo:* si
   `existing.date != _date`, `deleteCheckIn(existing.date)` en la misma
   transacción.

8. **Comidas registra en la fecha de ayer pasada la medianoche** —
   [meals_screen.dart:29](../lib/features/meals/meals_screen.dart#L29).
   `_day = dateOnly(DateTime.now())` en un `State` que vive en el
   `IndexedStack` toda la sesión. Combos y «repetir de ayer» (flujo de un
   toque) no miran el rótulo. Misma raíz que el hallazgo 12.

9. **Comparador de fotos con valor fuera de la lista** —
   [photos_screen.dart:164-171](../lib/features/body/photos_screen.dart#L164).
   El `DropdownButton.value` es una fecha en estado local; al borrar esa toma
   la lista cambia pero el valor no: assertion en debug, dropdown vacío en
   release. *Arreglo:* en `build`, si la fecha no está en `checkIns`,
   reasignar a última/primera.

10. **Controller liberado antes de que cierre el diálogo** —
    [reminders_screen.dart:183](../lib/features/settings/reminders_screen.dart#L183).
    `controller.dispose()` justo al resolver `showDialog`, mientras la ruta
    aún anima su salida y puede reconstruir el `TextField` («used after being
    disposed»). *Arreglo:* diálogo `StatefulWidget` dueño del controller.
    Mismo patrón en `_LimitingPicker`
    ([session_form_screen.dart:707](../lib/features/training/session_form_screen.dart#L707)).

### Media

11. **Alerta «Sesiones por debajo del plan» prematura** —
    [alerts.dart:26](../lib/domain/report/alerts.dart#L26) y
    [report_stats.dart:26](../lib/domain/report/report_stats.dart#L26).
    `expectedTraining` cuenta todos los días del rango, incluidos los que no
    han llegado; la alerta de comidas sí usa `elapsedDays`. Como Informe abre
    por defecto en la semana en curso, la alerta sale siempre a mitad de
    semana. *Arreglo:* `expectedTrainingElapsed` para la alerta; en el resumen
    mostrar «2/5 (3 días por delante)».

12. **«Hoy» congelado al crear el provider** —
    [providers.dart:110](../lib/app/providers.dart#L110) y
    [providers.dart:137](../lib/app/providers.dart#L137).
    `dayKey(DateTime.now())` se evalúa una vez; con la app abierta pasada la
    medianoche, Hoy muestra las comidas de ayer y los avisos se reprograman
    con la proteína del día anterior. *Arreglo:* `todayProvider` con timer a
    medianoche y `AppLifecycleState.resumed`, del que dependan Hoy, Comidas y
    la reprogramación.

13. **Umbrales del perfil que no mandan** —
    `cooldownTargetSec`, `measureIntervalMaxDays`, `neverToFailure` y
    `nextMeasurementDate` existen en `profiles` pero no se editan en Ajustes ni
    se leen: el informe usa `minCooldownSec = 60` fijo
    ([report_input.dart:15](../lib/domain/report/report_input.dart#L15)) y el
    cronómetro usa 360/180/60 s constantes
    ([guided_session_screen.dart:132](../lib/features/training/guided_session_screen.dart#L132))
    en vez de `minWarmupSec`/`cooldownTargetSec`. Los docs dicen que «los
    umbrales viven en el perfil». *Arreglo:* pasar el perfil al cronómetro y a
    `Targets`; exponer los campos en Ajustes o quitarlos.

14. **Rondas estimadas o incompletas fijan récord** —
    [report_repository.dart:88](../lib/data/repositories/report_repository.dart#L88),
    [training_repository.dart:222](../lib/data/repositories/training_repository.dart#L222),
    [dashboard_repository.dart:81](../lib/data/repositories/dashboard_repository.dart#L81).
    Las tres consultas de máximo no filtran `roundsEstimated` ni `incomplete`;
    el formulario sí lo hace al celebrar. Un «~9 (est.)» deja récord 9 en Hoy
    y en el informe. *Decisión de producto:* excluirlas (recomendado) o
    documentar que cuentan.

15. **Reprogramación de avisos pierde cambios** —
    [providers.dart:119-130](../lib/app/providers.dart#L119).
    Si llega un cambio mientras `reschedule()` corre, `pending` lo descarta y
    no se vuelve a ejecutar. `reminders_screen.dart:36` además llama
    `reschedule()` directo, sin esa protección. *Arreglo:* bandera `dirty` y
    bucle hasta quedar limpio; una sola puerta de entrada.

16. **Permiso de notificaciones pedido en cada arranque** —
    [app.dart:50](../lib/app/app.dart#L50). Si el usuario dijo no, el diálogo
    del sistema vuelve cada vez que abre la app. *Arreglo:* pedir una vez y
    dejar el enlace a ajustes del sistema en Ajustes.

17. **Escrituras sin manejo de errores** (sistémico) —
    `meal_form:163`, `football_form:42`, `measurement_form:80`,
    `plan_edit:32`, `photos:96-103`, `reminders:36,132,150`. Una
    `SqliteException` o un `PlatformException` de cámara queda en un future
    no observado: sin snack, sin pop, a veces sin volver. *Arreglo:* helper
    `guarded(context, future, {okMessage})` en `lib/ui/widgets.dart`;
    `retrieveLostData()` en fotos.

18. **Arranque sin red de seguridad** — [main.dart](../lib/main.dart).
    Siembra, `ensureDefaults` e `init` de notificaciones corren antes de
    `runApp` sin `try/catch`: una excepción deja pantalla blanca sin mensaje.
    *Arreglo:* `runZonedGuarded` + pantalla de error con opción de exportar la
    base.

19. **Fricción en diálogos numéricos** —
    `_QuantityDialog` ([meal_form_screen.dart:364](../lib/features/meals/meal_form_screen.dart#L364)),
    `_WeightDialog` (`body_screen:164`), `_FreeItemDialog` (`meal_form:436`),
    minutos de fútbol (`football_form:90`): sin `autofocus` ni texto
    preseleccionado. Tres gestos extra por alimento contra la meta de 30 s.
    *Arreglo:* `autofocus: true` + selección completa en `initState`.

20. **Confirmaciones donde ya existe «Deshacer»** —
    `meals_screen:203`, `foods_screen:44`, `body_screen:66` piden diálogo
    modal en acciones de un toque; `meals_screen:371` ya tiene `_undoable`.
    *Arreglo:* borrar directo + SnackBar «Deshacer».

21. **Búsqueda de alimentos sin tildes ni tokens** —
    [meal_form_screen.dart:292](../lib/features/meals/meal_form_screen.dart#L292).
    «platano» no encuentra «Plátano»; «pollo pechuga» no encuentra «Pechuga
    de pollo». *Arreglo:* normalizar diacríticos y comparar por tokens (helper
    en `domain`).

22. **Borrar un alimento vacía combos en silencio** —
    [foods_screen.dart:44](../lib/features/meals/foods_screen.dart#L44) +
    `CASCADE` en `meal_template_items`. El atajo «Cena con pan» cambia de
    macros sin aviso. *Arreglo:* listar combos afectados o impedir el borrado.

23. **Franja fija en el atajo «Comida» de Hoy** —
    [home_screen.dart:265](../lib/features/home/home_screen.dart#L265) usa
    `MealSlot.desayuno` mientras Comidas usa `slotForTime`.

24. **Peso: siempre hoy y duplicable** —
    [body_screen.dart:136](../lib/features/body/body_screen.dart#L136).
    No se puede anotar el peso de ayer; varios pesajes el mismo día duplican
    puntos en la gráfica. Además `weights.last` (`body_screen:210`) es el más
    antiguo de los últimos 90, no el primero: el «desde …» del hero miente
    pasados 90 registros. *Arreglo:* `DateTile` opcional, upsert por fecha,
    consulta `firstWeight()`.

25. **Gráficas y comparador** — `charts.dart:219-235` barras de ancho fijo se
    solapan en rangos > 14 días; `body_screen:127` y `charts_section:130`
    muestran «Brazo» para relajado y tensionado; `photos_screen:237` crea un
    `Future` nuevo por build y la imagen parpadea; `report_screen:73-78`
    permite «SEMANA 0» y negativas; `plan_screen:79` recarga el plan completo
    por tarjeta en cada build; `training_screen:196` muestra «DESCANSO» gris
    mientras carga.

### Baja

26. **Duplicación**: `lapDurationsOf` en `guided_session_screen.dart` repite
    `lapDurations` de `session_math.dart` (el archivo importa solo `meanSec`);
    `_typeFor` y `_sessionTypeFor` repetidos en dos pantallas;
    `PlanExerciseDraft.targetLabel` y `ScriptExercise.targetLabel` formatean
    lo mismo de dos formas; `DashboardRepository._streak` reimplementa
    `ReportStats.planFor`; colores `0xFF4EA8FF` / `0xFFFFB067` / `0xFF7ED957`
    repetidos en seis archivos aunque `theme.dart` ya los define.
27. **Validación de entrada**: `plan_edit:101-117` acepta negativos y
    `repsMin > repsMax`; `foods_screen:227` y `training_screen:152` aceptan
    cantidad 0 y meta 0 rondas; `_FreeItemDialog` acepta ítem con todo en 0 y
    dice «Añadir» al editar; `TimeTile` (`widgets.dart:190`) hace `int.parse`
    sobre la hora guardada (crash con un respaldo raro).
28. **Consultas N+1**: `ReportRepository.load` (2 consultas por sesión, 1 por
    versión, 1 por sitio), `PlanRepository.dayFor` (carga la versión completa
    y llama `versionNumber`, que vuelve a listar versiones),
    `DashboardRepository._streak` (todas las sesiones). Aceptable a esta
    escala; anotar para cuando el historial tenga años.
29. **CI no compila Android**: `ci.yml` analiza y prueba; solo `release.yml`
    hace `flutter build apk`. Un cambio en Gradle o el manifiesto se descubre
    al etiquetar. *Arreglo:* `flutter build apk --debug` en CI.
30. **Lints mínimos**: `flutter_lints` 3 con dos reglas extra. Sugerido:
    `strict-casts`, `strict-inference`, `strict-raw-types`,
    `prefer_final_locals`, `avoid_dynamic_calls`; `flutter_lints` 4 es
    compatible con Dart 3.4. `PopScope.onPopInvoked` ya está deprecado.
31. **Sin pruebas de widget**: la prueba retirada en `fe723c3` ya usaba
    `openInMemoryDatabase()` y aun así colgó (Windows y Linux). Causa
    probable: `flutter_test` corre en `FakeAsync` y la E/S real de drift no
    avanza sin `tester.runAsync`. Dos salidas: (a) envolver los `pump` con
    `tester.runAsync`; (b) mejor, probar pantallas sobreescribiendo los
    providers de repositorio con fakes en memoria, sin SQLite.
32. **Accesibilidad**: `IconButton` sin `tooltip` en ocho sitios;
    `_BigButton` y el `GestureDetector` de fotos sin `Semantics`.
33. **Higiene**: BOM UTF-8 en `pubspec.yaml` y `alerts.dart`;
    `description: "A new Flutter project."`; `android:label="seguimiento"` en
    minúscula; `seguimiento-v1.4.0.apk` (28 MB) suelto en la raíz (ignorado,
    pero obsoleto); temporales `.sqlite` del export nunca se borran;
    `photo_repository.add` deja huérfano el archivo anterior si cambia la
    extensión; `meal_form:384` ternario con ambas ramas iguales;
    `hasPermission()` devuelve true fuera de Android.
34. **Red en cada arranque**: `UpdateBanner` en Hoy consulta GitHub al abrir
    la app. Es lo documentado («una consulta GET»), pero conviene decir que es
    automática o limitarla a una vez al día.
35. **Dependencias congeladas**: Flutter 3.22 y drift 2.21 bloquean
    `flutter_local_notifications` 22, `riverpod` 3, `fl_chart` 1.x,
    `share_plus` 13, `file_picker` 13. El riesgo crece con el tiempo (parches
    de sqlite3, compatibilidad con Android nuevo). La suite de dominio y
    repositorios hace el salto razonablemente seguro.

### Documentación (deriva docs ↔ código)

La estructura de contexto es buena; el problema es que las fases 2–5 se
implementaron sin volver a los documentos de las fases 0–1. Lo que hoy es
falso:

| Documento | Dice | Realidad |
|---|---|---|
| `project-map.md:68` · `modelo-datos.md:56` | `schemaVersion` 1 | 6, migraciones 1→6 |
| `project-map.md:80,102-105` | 17 / 47 pruebas, migración 1→2 | 133 pruebas; `migration_test` cubre 1→6 y 2→6 |
| `project-map.md:43-44,99` | fotos, gráficas y recordatorios excluidos / en v2 | Los tres implementados; solo la nube sigue fuera |
| `project-map.md:4-5,37` | sin remoto; tema Material 3 por defecto | Remoto en GitHub; tema propio en `lib/ui/theme.dart` |
| `project-map.md` tabla de riesgos | Sin filas para notificaciones ni fotos | Faltan: receivers del manifiesto, alarma exacta, fotos fuera del respaldo |
| `auditoria-planeacion.md:68,70-72,79-85` | restauración pendiente; sin recordatorios; fotos sin tablas; pruebas de UI saltadas | Todo implementado; pruebas de UI retiradas, no saltadas |
| `README.md:11-16,33` | MVP sin recordatorios/fotos/gráficas/combos; Java 21 | Todo eso existe; Gradle y CI usan Java 17 |
| `README.md:29` · ADR 0001 | `share_plus ^10.1.4` | Fijado exacto `10.1.4` |
| `roadmap.md:38,57` | editor del plan sin variante | `plan_edit_screen.dart:190` ya edita agarre/variante; sostén y RIR siguen solo lectura |
| `modelo-datos.md:67` | v2 sin `variant` ni `notes` | `onUpgrade` también añade `plan_exercises.variant/notes` |
| `informe.md:61,72` | umbrales en el perfil; `minCooldownSec` | `minCooldownSec = 60` es constante (hallazgo 13) |
| `informe.md:78` | alerta «Sesión en día no planificado» | No existe; la cubre «Fuera de plan» |
| `informe.md:87` | «cuando existan fotos…» | Ya existen; el informe no las menciona |
| `notificaciones.md:44` | permiso pedido al primer arranque | En cada arranque mientras no esté concedido (hallazgo 16) |
| `cronometro.md:58-63` | fin de descanso solo en primer plano; notificaciones «en la siguiente fase» | Ya hay alarma exacta y canal `descanso`; contradice `notificaciones.md:15` |
| `actualizaciones.md:102-104` | Linux corre pruebas de UI | No hay; faltan pasos «Generar código» y «Borrar la llave» del workflow; trigger real `v*` + `workflow_dispatch` |

Correctos tras verificar: `comidas.md`, `diseno.md`, ADR 0004/0005, `INDEX.md`,
defaults de recordatorios, nombres de secrets y regla de etiqueta.

Decisiones durables sin ADR ni doc (conviene una línea en `modelo-datos.md`
o `notificaciones.md`): esquema de id de notificación
(`kind.index*1000 + día*24 + hora`), id fijo `90001` del fin de descanso
exento de la cancelación masiva, nombres de canales Android (`recordatorios`,
`descanso`: renombrarlos crea otro canal), horizonte de 7 días, fallback a UTC
si falla la zona horaria, regla «una foto por fecha y ángulo, la nueva
reemplaza», repo por defecto embebido en `config.dart`.

## Plan propuesto

| Fase | Qué | Criterio de cierre |
|---|---|---|
| **A. Corregir** (2–3 días) | Alta 2–10 y Media 11, 12, 14, 15, 16, 17, 23, con una prueba por hallazgo donde haya dominio o repositorio; docs al día (tabla anterior) | `flutter test` verde con pruebas nuevas; informe de la semana en curso sin alerta falsa; restore (éxito y fallo) verificado en el teléfono; fin de descanso verificado en segundo plano |
| **B. Robustecer** (3–4 días) | Persistencia de cronómetros (1); umbrales del perfil mandan (13); fricción de 30 s (19–22, 24); CI compila APK (29); spike de pruebas de widget (31); respaldo automático del roadmap | Matar la app a mitad de circuito y reanudar; un smoke test de UI en CI; registrar una comida de combo en ≤ 3 toques |
| **C. Modernizar** (1 semana, rama aparte) | Flutter estable actual + drift, notificaciones, riverpod, fl_chart, share_plus (35); lints estrictos (30); limpieza (25–28, 32–34) | Misma suite verde; APK firmado instala sobre 1.5.0 sin perder datos |

Orden recomendado: A → B → C. C es la más grande y conviene hacerla con A y B
cerradas, porque las pruebas nuevas de A y B son la red para C.

## Estado de cierre (23 sep 2026)

Trabajo en la rama `mejoras/auditoria-2026-09`, sin publicar. Commits:
fase A `0d541f3`; fase B `2bc154c`, `608c9fa`, `0d8cd4c`, `8c20526`; fase C
`f823fc1` y el cierre documental.

| Hallazgos | Estado | Evidencia |
|---|---|---|
| 1 cronómetros sin persistencia | Resuelto y verificado | Emulador Android 15 (24 sep): app matada en pleno descanso, "Retomar" vuelve al mismo descanso con el reloj al día |
| 2 alarma exacta Android 14+ | Resuelto y verificado | Emulador Android 15: sin permiso queda alarma inexacta (ventana ~1 min) y se avisa una vez; Recordatorios abre el ajuste; con permiso queda exacta y la notificación llegó a la hora exacta con la app en segundo plano |
| 3, 4, 5 restauración | Resuelto | `restore_test.dart` (incluye rollback) |
| 6 editor del plan | Resuelto | Claves por ejercicio y día; validación con prueba |
| 7 toma duplicada | Resuelto | Prueba de repositorio |
| 8, 12 «hoy» congelado | Resuelto | `todayProvider`; sin prueba automática de medianoche |
| 9 comparador de fotos | Resuelto | Sin prueba automática |
| 10 controllers de diálogos | Resuelto | `promptText` y diálogo de umbral dueños del controller |
| 11 alerta a mitad de semana | Resuelto | Pruebas de semana en curso |
| 13 umbrales del perfil | Resuelto | `measurementDue` con pruebas; metas en Ajustes |
| 14 récord con estimadas | Resuelto (decisión: estimadas no cuentan, incompletas sí) | Pruebas de dominio y repositorio |
| 15 reprogramación | Resuelto | `coalesce` con pruebas |
| 16 permiso en cada arranque | Resuelto | Bandera local |
| 17 escrituras sin error | Resuelto | `guarded` en guardados, borrados y copias (24 sep) |
| 18 arranque sin red | Resuelto | Pantalla de error con exportación de rescate |
| 19–24 fricción | Resuelto | Búsqueda con pruebas; pesaje por día con pruebas |
| 25 gráficas y pantallas | Resuelto | Pruebas de pantalla cargan Informe |
| 26 duplicación | Resuelto salvo `targetLabel` doble (formatos distintos a propósito) y `_streak` | — |
| 27 validación | Resuelto | — |
| 28 N+1 | Resuelto en el informe; `PlanRepository.dayFor` sigue cargando la versión completa | Aceptable a esta escala |
| 29 CI sin APK | Resuelto | `ci.yml` compila debug |
| 30 lints | Resuelto | `flutter analyze` limpio con reglas estrictas |
| 31 pruebas de widget | Resuelto | 4 pruebas de pantalla; causa documentada en README |
| 32 accesibilidad | Resuelto | Tooltips y `Semantics` |
| 33 higiene | Resuelto | — |
| 34 red al arrancar | Documentado (decisión: se mantiene automático) | `project-map.md` |
| 35 dependencias | **Abierto** | Ver abajo |
| Docs | Resuelto | Tabla de deriva aplicada |

## Salto de SDK (pendiente, requiere decisión)

No se hizo. Subir Flutter cambia la herramienta global del equipo
(`C:lutter`), el SDK fijado en `ci.yml` y `release.yml` y, con él, la cadena
de releases firmadas. Dentro de 3.22 no hay subidas seguras: `fl_chart` 0.71 y
`share_plus` 12 se probaron y no compilan, aunque `pub` los resuelve.

Orden propuesto, en una rama propia y con la suite actual como red:

1. Instalar el Flutter estable nuevo **aparte** (fvm o una carpeta propia),
   sin tocar `C:lutter`.
2. Subir Java/AGP/Kotlin/Gradle a lo que pida esa versión; `compileSdk 35` y
   NDK que ya piden los plugins (aviso actual del build).
3. Soltar `drift`/`drift_dev`, `sqlite3`/`sqlite3_flutter_libs` (la 0.5 está
   marcada EOL), `fl_chart`, `share_plus` (`SharePlus.instance.share`),
   `file_picker`, `package_info_plus`. Regenerar con `build_runner`.
4. `flutter_local_notifications` 19+ (quita `uiLocalNotificationDateInterpretation`)
   junto con `timezone` y `flutter_timezone`: probar en el teléfono los ocho
   avisos y el fin de descanso con pantalla apagada.
5. Riverpod 3 al final y aparte: cambia `StateProvider` y la forma de los
   providers; es el cambio más grande en líneas.
6. Gate: `flutter analyze`, `flutter test` (176+), APK de release firmado
   instalado **encima** de 1.5.0 conservando datos, y una semana de uso.

## Verificación en emulador (24 sep 2026)

Android 15 (API 35), app instalada encima de una base real del esquema 6:

- La migración al esquema 7 abrió sin errores y conservó los datos.
- Cronómetro: reps por ejercicio, descanso aparte del neto (los tiempos
  suman el total), kcal con 70 kg (≈ 2 kcal a los 22 s, lo que da la fórmula).
- Retomar tras matar el proceso en pleno descanso: mismo paso, reloj al día.
- Alarma exacta: comportamiento de los dos casos, notificación puntual.
- Copia automática: una en la primera apertura del día, ninguna al reabrir.

La verificación encontró dos defectos que venían de antes y quedaron
corregidos con pruebas: "Terminar" guardaba la sesión como completa (en
circuitos, con todas las rondas del plan), y al salir del cronómetro el aviso
de descanso no se cancelaba. Si alguna sesión anterior a la 1.7 se cerró con
"Terminar", sus rondas pueden estar infladas: conviene revisarlas en Entreno.
