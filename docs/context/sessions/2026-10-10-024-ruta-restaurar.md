# Recibo 024 — barrera de entrada con ruta abierta al restaurar

Fecha 10 oct 2026. Misma sesión Claude `f52ad7a7-a40b-4036-8114-99689fa02ce2`,
worktree `C:/My Projects/seguimiento-claude-022`, rama
`JuxnD/022-alta-neutral-claude`, **base congelada**
`8872ae2b235d46dbc9b81f43f39af8f0c2827372`. Flutter 3.22.0/Dart 3.4 fijo.
Sin push, merge, APK, AVD, teléfono, backend ni datos reales; no se tocaron
otras ramas/WT, integración 535/b327, lectores 023 ni fuente 011.

## Alcance

Sólo `lib/features/onboarding/app_entry.dart`,
`lib/features/settings/restore_access.dart` y pruebas. `app.dart` no cambió.
Esquema, metas, origen, parser, journal y datos de 022 intactos.

## Prueba y rojo (ciclo formal 1, código 8872 sin cambios)

`test/ui/pilot_restore_route_test.dart` (SHA256
`a6f6fecae33718461bbb62072d5e4d0fa211a5ff0f5768cdc3a07d6cf6dd7596`):
`SeguimientoApp` real → Hoy → Ajustes → acción, con SQLite/BackupArchive/
DatabaseHost/ProfileRepository reales; espías sólo de permisos, avisos, pasos y
respaldo semanal; guion `CounterSnapshot`, foto y flags en disco. La espera
exige restauración REAL completada (sin diálogos, generación observada y
estado del alta releído sin carga) antes de los oráculos visibles. Cinco casos:

| Caso | 8872 | Reparado |
|---|---|---|
| SQL pendiente (escrituras Drift + generación) con Ajustes encima | rojo: «alta VISIBLE» 0 | verde |
| ZIP pendiente real (picker, confirmación UI, restore) | rojo: «alta VISIBLE» 0 tras completar gen 1, pending, 0 metas/personales, guion y flags idénticos, efectos 0, avisos [] | verde |
| ZIP listo real (ready→ready) | verde: Ajustes sigue, datos del respaldo | verde |
| Cancelar confirmación | verde: gen 0, base/foto/flags/guion iguales | verde |
| Fallo tardío (opener falla una vez) | verde: rollback, alta lista, Ajustes y foto intactos | verde |

[JSON del rojo](evidence/2026-10-10-024-red-8872.json), SHA256
`304332ff1dbd6d183f0e76c1e2ef0e5473eb17efb40a6203610c5ae68f7a9adf`.
Una corrida previa falló en «flags intactos» por harness (la referencia se
tomó antes de que llegara al disco la escritura `notificationsAsked` del
arranque); se corrigió esperando esa escritura, sin cambiar oráculos ni
producción. El cuelgue de 20 s del probe revisor **no se reprodujo** en este
harness (los cinco casos completaron la restauración); su causa sigue
NO_CONFIRMADA y no se atribuye a SQLite. No se repitió el probe ZIP revisor.

## Reparación (ciclo formal 2)

- AppEntry: al pasar de listo a pendiente (`AsyncData` no listo) o a error
  (`AsyncError`) retira avisos (pendiente) y cierra rutas con
  `Navigator.of(context).popUntil(isFirst)` desde su contexto. Sin
  `navigatorKey` global. Listo→listo, cancelación y rollback no navegan.
- `restoreBackupFile`: host, documentos y notifier de generación se capturan
  antes de cualquier `await`; confirmación y progreso se cierran como antes.

## Supresión de avisos Drift

Retirada `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true` sólo en
`test/data/pilot_profile_test.dart` y `test/ui/pilot_onboarding_test.dart`; la
prueba nueva tampoco la usa. Supresiones históricas fuera de alcance intactas.
Los avisos quedan visibles (33 en los dirigidos; vienen de la apertura de
prueba del respaldo y de bases sintéticas por persona).

## Gates

```text
flutter test test/ui/pilot_restore_route_test.dart       8872: +3 -2 · reparado: +5
flutter test pilot_profile + pilot_onboarding + pilot_restore_route
             + app_smoke + backup_settings + backup_archive  +81 -0 (33 WARNING drift)
flutter analyze                                           No issues found
flutter test (completa, una vez tras la reparación)      +872 ~17 -2 (exit 1, ver «Suite»)
git diff --check                                          limpio
```

## Suite

Suite completa, una vez tras la reparación: **+872 ~17 -2, exit 1**, en 5:41
(la full de 8872 tardó 1:29; host probablemente cargado, causa NO_CONFIRMADA).
Los 2 fallos son sólo de la prueba nueva, en sus esperas de 20 s de reloj real:
SQL pendiente en «flags del arranque escritos» y ZIP pendiente en «restauración
completada». ZIP listo, cancelar y rollback pasaron también bajo carga, y el
resto de la suite queda en 0 fallos. La misma prueba pasó aislada (+5, JSON
`29cef02e…92eb`) y en la corrida dirigida (+81, `677e7b9e…e995`). Full:
`build/024-full.json` `126e7f09…aa56` (ignorado, local).

Se aplicó STOP: se usaron los 2 ciclos formales y no se permite subir el
timeout. No se probó un tercer ciclo ni se cambiaron las esperas. Hipótesis
NO_EVALUADA: los límites de 20 s de reloj real son sensibles a la contención,
igual que el cuelgue de 20 s del probe revisor. Decisión pendiente del
coordinador/revisor: estabilizar el harness (espera basada en progreso, o
ejecutar este archivo en serie) o repetir la full con el host libre.

La full 869/17 de `8872` no acredita este árbol ni la prueba nueva.

## Límites

Nativo/APK/teléfono NO_EVALUADO. Cierre 012 de lectores sigue pendiente.
Licencia: no forma parte del ZIP ni de estas rutas; sin prueba propia aquí.
