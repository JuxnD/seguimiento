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
| `exercises` | Catálogo de ejercicios | Nombre único sin distinguir mayúsculas (se normalizan espacios) |
| `plan_versions` | Versión del plan vigente desde `validFrom` | **Inmutable**: editar crea otra versión |
| `plan_days` | Un día por versión (1 = lunes … 7 = domingo) | Único `(planVersionId, weekday)` |
| `plan_exercises` | Ejercicios del día con series/reps/descanso | `position` ordena |
| `sessions` | Sesión registrada | `roundsEstimated` marca rondas calculadas, no contadas |
| `session_rounds` | Marca acumulada (s) al cerrar cada ronda | Procede del contador; permite la media real por ronda |
| `session_sets` | Serie por ejercicio | `setIndex` es por ejercicio dentro de la sesión |
| `football_games` | Partido aparte de las sesiones | Formato 5 o 7 |
| `foods` | Catálogo con macros por unidad o por 100 g/ml | `basis` decide cómo se multiplica la cantidad |
| `meals` / `meal_items` | Comida y sus alimentos | Los macros del item son **copia**, no referencia |
| `body_weights` | Pesajes | `fasted` distingue la condición |
| `measurements` | Una medida por sitio y fecha | Único `(date, site)`: una toma por día |
| `week_notes` | Notas libres por semana | La clave es el índice de semana anclado al inicio |

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

`schemaVersion` vale **1**. Al cambiar una tabla:

1. Subir `schemaVersion` en [`lib/data/database.dart`](../lib/data/database.dart).
2. Añadir el paso en `onUpgrade` (`m.addColumn`, `m.createTable`, …).
3. Anotar aquí qué cambió y por qué.
4. Correr `dart run build_runner build --delete-conflicting-outputs`.
5. Probar el salto de versión con datos reales exportados, no solo con base nueva.

| Versión | Cambio |
|---|---|
| 1 | Esquema inicial del MVP |

## Respaldo

Ajustes → *Exportar base de datos* usa `VACUUM INTO`, que produce una copia
consistente incluso con el WAL abierto. La restauración aún no está en la app:
hoy se recupera reemplazando el archivo `seguimiento.sqlite` del directorio de
documentos de la app. Ver [roadmap.md](roadmap.md).
