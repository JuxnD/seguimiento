# Checkpoint122 · avisos de molestias y Cindy de prueba

Worktree `C:/My Projects/seguimiento-122-integracion`, rama
`JuxnD/122-integracion`; base `f0df77c4f1220dd9fb8f8a859d37bced589bdb8a`.
Tramo separado del [checkpoint015](2026-10-10-integracion-122-015.md).
Sin APK, AVD, teléfono, backend, push/deploy ni publicación. Esquema21 y
Flutter3.22 conservados. No incorpora009WIP/22 ni SDK017/018.

## Fuente y reconciliación

FuenteClaude revisada por el coordinador: worktree `seguimiento-claude-c01`,
HEAD `adbaeccbe57af5a6a487372e864f910b4725ba6b`, sólo buzón de planes sin track.
No se modificó esa raíz. Integraciones:

- `f38295f35213dc9e2b2c0612a58279375a797f97` → `bfb2abc`: una molestia
  reciente genera un aviso; no agrega ejercicios ni rehace el bloque.
- `95d04234e8ad42a4402e6b7d5c697efcad7ffc3a` → `f0cd0d6`: pruebas de lectura
  SQLite y aviso. El caso UI original usa `_Sore`; no se toma como prueba
  SQLite→pantalla por sí solo.
- `adbaeccbe57af5a6a487372e864f910b4725ba6b` → `1c94fcb`: Cindy de prueba
  muestra «Antes del intento» en calentamiento y conserva visible el botón.
  Cindy normal y Tabata no muestran esa tarjeta.

Sólo conflicto documental en ADR0015: se actualizó la antigua limitación de
Cindy y conservó íntegro el apéndice014 que resolvía las seis figuras ausentes.
Guía auto-mergeada releída: comparación de modos008 y registro/snapshot intactos.
No se reinterpretan molestias como técnica aprobada ni notas como completitud.

Ampliación autorizada únicamente en `test/ui/guided_warmup_test.dart`: un caso
usa `RecoveryRepository(db)` real, `setSoreness` y pantalla. Hombro5 de ayer
avisa; Rodilla2 y Codo de cuatro días atrás no. Exige las siete etiquetas con
su dosis, ausencia de Dislocaciones, cero pasos completos y snapshot sin marcas
ni salto. No duplica en el test el filtro de fecha que hace la pantalla.

Adaptación mecánica014 en `test/ui/illustration_catalog_coverage_test.dart`:
se quitó sólo `warmupForZone.values`, retirado porClaude. El oráculo sigue
leyendo guías, escaleras, movilidad y `buildWarmup` real; no lee el catálogo
para fabricar su inventario esperado ni restaura recetas por dolor.

## Gates y diagnóstico conservado

- [18 casos](122-warmup-focused-final.txt), exit0, sin skips: los17 del handoff
  y la nueva costura real. Incluye aviso, dosis/40%/descanso, salto, foto legada,
  Cindy checklist/botón, reanudación Cindy/Tabata y ronda parcial al reabrir.
- [24 controles compartidos](122-warmup-shared-controls.txt), exit0: cobertura,
  CTA360 texto1.6/2.0, rig/73 geometrías, guardado/descanso/fases de guía y
  serialización/cola física de snapshots.
- [Paridad](122-warmup-parity.json):79 entradas,73 objetos históricos idénticos,
  generación determinista, SHA256
  `1ee6e443f42f91fa3096af7a3006de374f45334ca25400e924e5e5376c3d992a`.
- [Recursos013](122-warmup-icons.txt):25 PNG nativos y5 fuente verificados
  contra el recibo original; no se cambia el logo ni sus hashes.
- [Análisis final](122-warmup-analyze-final.txt), exit0, sin incidencias;
  `git diff --check`, exit0. No hay diff de este tramo en Android, esquema,
  pubspec/lock, catálogo generado ni firma.

La [primera ejecución](122-warmup-focused.txt) no fue verde: el caso histórico
de salto leyó `warmupSkipped=false` y el nuevo caso no terminó. Se interrumpió
el proceso; no se borró el fallo ni se ampliaron tiempos. El salto pasó después
sin cambio en sus assertions/espera; su primer fallo tiene causa desconocida,
no se atribuye por conveniencia a IO.

El [diagnóstico aislado](122-warmup-sqlite-diagnostic.txt) llegó a todas las
assertions y se detuvo al cerrar. El [diagnóstico de cierre autorizado](122-warmup-sqlite-close-diagnostic.txt)
terminó exit0 en6s, con trazas seed→pantalla→assertions→desmontaje→close.
Se reutiliza el patrón ya revisado015: desmontar, bombear un frame, iniciar
`db.close`, bombear y esperar su completion. Se limita al caso nuevo y se
ejecuta en `finally`; no cambia producción ni los teardowns históricos.

**Diagnóstico BLOCKED; mutante NO_EVALUADO:** la copia temporal conecta el provider
a otro SQLite vacío. Dos montajes se detuvieron durante el cierre; el segundo
llegó al oráculo del aviso, pero Flutter no emitió la assertion antes del
`finally` pendiente. No cuentan como rojo funcional. Se conserva
[primer harness](122-warmup-connection-mutant-first.dart.txt),
[primer log](122-warmup-connection-mutant-red.txt),
[segundo harness](122-warmup-connection-mutant.dart.txt) y
[segundo log](122-warmup-connection-mutant-initialized-red.txt).
STOP informado al coordinador antes de una tercera ejecución. El coordinador
releyó el harness y autorizó una reapertura diagnóstica distinta: ambos cierres
iniciados antes del pump, trazas por cada DB, `Future.wait` después del pump.
El [harness final](122-warmup-connection-mutant-close-diagnostic.dart.txt) y
[salida final](122-warmup-connection-mutant-close-diagnostic.txt) muestran que
el desmontaje termina y que la DB vacía cierra; el cierre de la DB fuente no
reporta completion. Eso refuta atribuir el bloqueo a la DB vacía sólo por la
hipótesis inicial, pero todavía no establece la causa de la espera.
La ejecución se interrumpió y se cerró este enfoque como BLOCKED, por la
instrucción del coordinador; no habrá más intentos ciegos. No se cuenta el
exit1 de interrupción como rejection de una assertion. Aunque algunos nombres
de logs conservan el sufijo `red`, su contenido no acredita rojo funcional.
Copias temporales retiradas de `test/ui`; producción y assertions intactas.

## Reejecución

Desde la raíz aislada, con SDK fijado:

```powershell
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency 1 --reporter expanded test/domain/warmup_test.dart test/data/warmup_soreness_data_test.dart test/ui/guided_warmup_test.dart test/ui/v3_timers_test.dart
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency 1 --reporter expanded test/ui/illustration_catalog_coverage_test.dart test/ui/illustration_controls_readability_test.dart test/ui/illustration_warmup_rig_test.dart test/ui/illustration_legacy_parity_test.dart test/ui/guided_session_test.dart test/domain/active_session_test.dart test/data/active_session_store_test.dart
python build/122_014_parity.py
python tool/icon_verify.py
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' analyze --no-pub
git diff --check
```

El harness de paridad está archivado en `122-014-parity.py.txt`; los mutantes
están fuera de la suite y se seleccionan por `--plain-name 'SQLite a pantalla'`.
Al archivar, `git diff --cached --check` detectó espacios finales emitidos por
Flutter/Drift. Sólo se normalizaron esos espacios y UTF8/LF de los logs; no se
quitaron warnings, assertions o fallos. [Hashes antes/después](122-warmup-log-normalization.json).
No se ejecuta full hasta que el coordinador cierre la fuente candidata.
Implementación integrada y positivos verificados localmente; sensibilidad
negativa de esta conexión NO_EVALUADO, APK,
Manifest fusionado, continuidad instalada y comprensión humana siguen abiertos.
