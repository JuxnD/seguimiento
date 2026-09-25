# Modelo de datos

SQLite local mediante `drift`. Definición: [`lib/data/tables.dart`](../lib/data/tables.dart).
El código generado (`database.g.dart`) no se edita a mano.

## Convenciones

| Cosa | Cómo se guarda | Por qué |
|---|---|---|
| Fecha | Texto `YYYY-MM-DD` (día local) | Un día registrado nunca cambia por zona horaria ni por horario de verano |
| Hora | Texto `HH:mm` | Se ordena bien y se lee sin conversión |
| Duración | Entero en segundos | El informe formatea `mm:ss` |
| Longitud | `double` en **cm** | Se muestra en la unidad del perfil; se guarda una sola |
| Peso | `double` en kg | — |
| Enum | Texto con el nombre del valor | Renombrar un valor exige migración; añadir valores al final es seguro |

## Tablas

| Tabla | Qué guarda | Invariante |
|---|---|---|
| `profiles` | Fila única (id = 1): inicio, metas, umbrales, unidad | Siempre existe; se crea al abrir la base |
| `exercises` | Catálogo de ejercicios, con claves de técnica (una por línea), enlace de referencia, nota de progresión y si progresa con carga | Nombre único sin distinguir mayúsculas (se normalizan espacios); las guías viven aquí y no en el plan, que es inmutable |
| `plan_versions` | Versión del plan vigente desde `validFrom` | **Inmutable**: editar crea otra versión |
| `plan_days` | Un día por versión (1 = lunes … 7 = domingo), con rondas objetivo y descanso entre rondas | Único `(planVersionId, weekday)` |
| `plan_exercises` | Ejercicios del día: series, reps o sostén, descanso (rango), agarre, RIR, por lado, bloque extra y variante | `position` ordena; `block = null` es el trabajo principal |
| `sessions` | Sesión registrada, con el cierre y el plan que regía | `roundsEstimated` marca rondas calculadas, no contadas; `techniqueOk`/`fullRange`/`recoveryOk` en `null` significan "no registrado", no "mal" |
| `session_rounds` | Marca acumulada (s) al cerrar cada ronda, trabajo de la ronda y descanso posterior | `work_sec`/`rest_sec` en `null` = no se midió (antes del esquema 8 o contador libre); la vuelta sola mezcla el descanso previo |
| `session_sets` | Serie por ejercicio, con carga externa opcional | `setIndex` es por ejercicio dentro de la sesión; `load_kg` null = peso corporal |
| `football_games` | Partido aparte de las sesiones | Formato 5 o 7 |
| `foods` | Catálogo con macros por unidad o por 100 g/ml, con la procedencia de las cifras | `basis` decide cómo se multiplica la cantidad; `source` distingue etiqueta de referencia |
| `meal_templates` / `meal_template_items` | Combos de un toque (batido, cena base…) | Referencian el catálogo; no anidan otros combos |
| `meals` / `meal_items` | Comida y sus alimentos | Los macros del item son **copia**, no referencia; `sourceVerified` recuerda si venían de etiqueta (null = entrada libre) |
| `body_weights` | Pesajes | `fasted` distingue la condición |
| `measurements` | Una medida por sitio y fecha | Único `(date, site)`: una toma por día |
| `progress_photos` | Fotos de progreso por fecha y ángulo | Guarda la ruta **relativa** al directorio de la app: las absolutas se rompen al reinstalar |
| `reminders` | Ajustes de cada recordatorio (activo, hora, umbral) | Una fila por tipo; `ensureDefaults` crea las que falten sin pisar lo editado |
| `week_notes` | Notas libres por semana | La clave es el índice de semana anclado al inicio |
| `closed_days` | Días de comida cerrados a mano | Un día con desayuno, almuerzo y cena ya cuenta como cerrado sin estar aquí |

## Decisiones que el esquema hace cumplir

- **Historial a prueba de ediciones.** `meal_items` congela los macros: cambiar
  el catálogo (o borrar un alimento) no reescribe lo ya registrado.
  `foodId` queda en `NULL` al borrar el alimento.
  Ver [adr/0002](adr/0002-snapshot-macros-en-comidas.md).
- **El plan es versionado, no editable.** El informe puede decir qué se
  esperaba cada día aunque el plan haya cambiado a mitad de semana.
  Ver [adr/0003](adr/0003-versiones-de-plan-inmutables.md).
- **Ejercicios por catálogo, no por texto libre.** Es lo que permite la alerta
  "Flexiones partidas en 3 sesiones" sin que "flexiones" y "Flexiones" cuenten
  como ejercicios distintos.
- **Integridad referencial activa.** `PRAGMA foreign_keys = ON` en `beforeOpen`;
  borrar una sesión borra sus series y vueltas (`CASCADE`).

## Migraciones

`schemaVersion` vale **9**. Al cambiar una tabla:

1. Subir `schemaVersion` en [`lib/data/database.dart`](../lib/data/database.dart).
2. Añadir el paso en `onUpgrade` (`m.addColumn`, `m.createTable`, …).
3. Anotar aquí qué cambió y por qué.
4. Correr `dart run build_runner build --delete-conflicting-outputs`.
5. Probar el salto de versión con datos reales exportados, no solo con base nueva.

| Versión | Cambio |
|---|---|
| 1 | Esquema inicial del MVP |
| 2 | Plan con bloques extra, variante A/B, notas, sostenes, RIR, por lado y descanso en rango; día con descanso entre rondas; sesión con las condiciones de la regla de progresión; perfil con ventana de medición, enfriamiento objetivo y regla de no llegar al fallo |
| 3 | Alimento con gramos por porción y procedencia (`etiqueta` / `referencia`); ítem de comida con `sourceVerified`; tablas de combos |
| 4 | Sesión con `outOfPlan`, `incomplete` y `plannedRounds`: distingue entrenar otra cosa de cerrar antes de tiempo |
| 5 | Tabla `reminders` con los ajustes de notificaciones |
| 6 | Tabla `progress_photos` |
| 7 | `sessions.rest_sec`: descansos sumados, aparte del trabajo neto (0 en sesiones anteriores) |
| 8 | Ronda con trabajo y descanso; serie con carga; ejercicio con claves de técnica, enlace, progresión y carga; tabla `closed_days`. La migración también completa las guías de los ejercicios existentes y añade al catálogo el almuerzo corriente, el peto y el salchichón ([`catalog_updates.dart`](../lib/data/catalog_updates.dart)) sin pisar lo del usuario |
| 9 | Solo datos: los recordatorios vuelven **una vez** a los valores acordados el 26 sep 2026 (se borran las filas y el arranque las recrea). Restaurar un respaldo también recrea las que falten |

Los saltos 1 → 9, 2 → 9, 6 → 9, 7 → 9 y 8 → 9 están cubiertos por
[`test/data/migration_test.dart`](../test/data/migration_test.dart): una base
vieja con datos se abre, conserva lo registrado y queda en `user_version = 9`.
El 6 → 8 se verificó además en el emulador (Android 15) con la base de la 1.6.1.

**Récord de rondas.** Una sola definición en
`AppDatabase.countedCircuitRounds`: sesiones de circuito con rondas
**contadas**. Las estimadas por tiempo no son marca; las de una sesión cerrada
antes de tiempo sí (esas rondas se hicieron). La usan Hoy, el cierre de sesión
y el informe.

**Qué no vive en la base.** Las banderas del dispositivo (si ya se pidió el
permiso de notificaciones, fecha del último respaldo automático y de la
última consulta a GitHub) van en `flags.json` en el directorio de soporte de la
app ([`local_flags.dart`](../lib/data/local_flags.dart)). Restaurar un respaldo
no las toca, a propósito.

## Siembra inicial

En la primera apertura:

- [`seed_plan.dart`](../lib/data/seed_plan.dart) crea las dos versiones del plan
  y fija las metas del perfil.
- [`seed_foods.dart`](../lib/data/seed_foods.dart) crea el catálogo (33
  alimentos) y los combos frecuentes.
- [`catalog_updates.dart`](../lib/data/catalog_updates.dart) completa las guías
  de técnica de los ejercicios del plan.

Ambas son idempotentes: si ya hay plan o alimentos, no tocan nada, así que
nunca pisan lo que el usuario edite.

**Cómo se guarda cada alimento.** Lo que se mide en gramos o mililitros se
normaliza a 100 (la cantidad se escribe en g/ml y `defaultQuantity` deja
prellenada la porción habitual: 40 g de avena, 250 ml de jugo). Lo que se cuenta
por piezas —huevo, lata, papeleta, vaso— guarda los macros de **una** unidad.
Esa decisión es la que permite escribir "150 g de arroz" y "3 huevos" sin
convertir nada mentalmente.

## Respaldo

**Las fotos no van en el respaldo.** El archivo exportado es la base de datos:
las imágenes viven aparte, en el directorio de la app. Si cambias de teléfono,
cópialas por tu cuenta o vuelve a tomarlas.

Ajustes → *Exportar base de datos* usa `VACUUM INTO`, que produce una copia
consistente incluso con el WAL abierto. Ajustes → *Restaurar desde un respaldo*
valida el archivo, reemplaza la base y hace rollback si algo falla. El detalle
del procedimiento está en [actualizaciones.md](actualizaciones.md).

Un respaldo con `user_version` mayor que el `schemaVersion` de la app se
rechaza: es de una versión más nueva y restaurarlo rompería los datos.
