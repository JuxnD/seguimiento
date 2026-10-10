# Checkpoint122 · avisos de molestias y Cindy de prueba

**Revisión independiente abierta:** el coordinador no aprueba aún el cierre
completo del checkpoint. En HEAD9c0de20 obtuvo16 casos que pasan y2 fallos de
snapshot histórico. La evidencia positiva previa se conserva como esa ejecución,
no como aprobación vigente. Diagnóstico de la barrera de guardado abajo.

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
Implementación integrada; la revisión de snapshots permanece abierta. Sensibilidad
negativa de esta conexión NO_EVALUADO, APK,
Manifest fusionado, continuidad instalada y comprensión humana siguen abiertos.

## Revisión independiente: barrera UI→archivo

El coordinador informó una repetición limpia en9c0de20, sesión37836, exit1:
16 pasan y2 fallan. «Pasos con dosis» leyó `warmupDone:[]` aunque la pantalla
ya marcaba2de7; «saltar» leyó `warmupSkipped:false` tras el botón. Este párrafo
registra el resultado entregado porRoot; no inventa ni reconstruye un log
completo que el coordinador no guardó. Coincide con la familia del primer fallo
conservado y no se borra por la repetición local que había pasado.

[Instrumentación aislada](122-warmup-store-race-diagnostic.dart.txt) sólo en
el test: subclase deActiveSessionStore llama `super.save`, devuelve la misma
Future, observa emitted/completion, instancia/ruta y archivo físico. No hace
otro save, no reemplaza ni cambia el orden del writer de producción. Conserva
el raw capturado tras el flush antiguo para la assertion original; una espera
diagnóstica posterior, limitada5s, no sustituye ese raw por el nuevo.

[Salida](122-warmup-store-race-diagnostic.txt), exit0,3 casos: el regex previsto
para los dos históricos también seleccionó el legado por su nombre. No se
declara como reproducer rojo del fallo justo después de20ticks. La traza sí
expone una ventana real: emitted#3 ya contiene ambas marcas, pero completion#1
conserva archivo vacío de marcas y pendientes2/3; completion#3 termina con ambas
marcas. Para salto, emitted#2 estrue, completion#1 aúnfalse con2pendiente y
completion#2 termina entrue. Instancia/ruta son las mismas, sin future-error
y sin tmp residual al completion final. En esta corrida el flush antiguo ya
alcanzó `pending:[]`, así no reproduce el punto exacto del fallo independiente
ni atribuye su causa por la mera repetición verde.

La ventana observada y la espera fija sin conocer completion son evidencia de
que la barrera antigua no acredita persistencia. Error tragado o rename fallido
no aparecieron en esta traza; no se afirma imposibilidad general. **Causa exacta
de los fallos anteriores NO_CONFIRMADA.** El coordinador leyó el resultado y
autorizó la barrera observable siguiente; mutante2DB BLOCKED sin reapertura.

## Barrera observable autorizada en el harness

`_ObservedStore.save` llama al escritor real y devuelve EXACTAMENTE la misma
Future de `super.save`. Registra último id emitido/completado, Future emitida,
pendientes y eventual error. No contiene archivo alterno ni otro guardado.
`flushStore` reemplaza20ticks fijos por condición: al menos un save real emitido,
último completado igual al emitido y conjunto pendiente vacío. Bombea el reloj
fake y cede al IO sólo mientras esa condición esté pendiente; `Stopwatch` falla
al llegar5s, dentro de la cota original del widgettest. No se amplió ningún
timeout, no se suprimió el warningDrift ni se modifica writer/producción.

Después de esa completion los casos siguen leyendo físicamente el archivo con
`File.readAsString`; no usan el snapshot del spy ni un `load` sustituto. Se
conservan EXACTAS las assertions de `aproximacion:Flexiones`, salto y draft.
Si un save termina pero el archivo sigue viejo, esas assertions aún deben fallar;
la barrera no fabrica el oráculo ni afirma que el writer tragado pueda validarse
por la mera Future. Se aplica sólo a casos de este archivo que ya usabanflushStore.

- [18 dirigidos](122-warmup-store-barrier-focused.txt), exit0, sin skips,
  primera ejecución con la nueva barrera. No hubo reintentos hasta pasar.
- [8 controlesStore/snapshot](122-warmup-store-barrier-controls.txt), exit0,
  sin skips: última foto, clear, corrupción y serialización legada.
- [Análisis](122-warmup-store-barrier-analyze.txt) exit0, sin incidencias, y
  `git diff --check` exit0. Logs archivados sólo con espacios finales yUTF8/LF
  normalizados; [hashes antes/después](122-warmup-store-log-normalization.json).
  Sin full nuevo,
  APK, AVD, teléfono, push o producción. Revisión independiente posterior
  pendiente; no se hereda la aprobación de otra ejecución.

Reejecución adicional:

```powershell
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency 1 --reporter expanded test/data/active_session_store_test.dart test/domain/active_session_test.dart
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --reporter expanded test/ui/guided_warmup_test.dart --name 'calentamiento guiado:|saltar el calentamiento'
```

El segundo comando documenta la instrumentación archivada (3casos seleccionados);
con el archivo actual ejecuta las mismas assertions mediante la nueva barrera.
No se reconstruye un rojo anterior ni se reabre el mutante2DB.
