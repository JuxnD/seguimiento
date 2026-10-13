# Entrega local de integridad026/027/028/029 — 12oct2026

Owner autorizó implementación conjunta Codex–Claude. Worktree de entrega
C:/My Projects/seguimiento-026-integridad, ramaJuxnD/026-integridad-diaria,
base433f64f. Sin alterar checkout diario/main ni worktreeClaude congelado.

## Composición y decisiones

Codex026: cd6de7b/9ce6725;028:60c704c/5b184b7. Revisiones asesor aprobadas:
44dirigidos independientes,5Python/79PHP/interop1/0skip.
Claude027: fe0b565/8b1cac5/74c26aa, incorporados como aff1bdc/2cce16a/31b0d0e.
Único conflicto.gitattributes resuelto conservando011/gateway/027;29archivos
de evidencia027 reexportados desde Git74c26aa para recuperar bytes exactos,
sin editar rawlogs.27logs verifican manifest en workingcopy y Git31b0d0e.

Fotos atómicas, snapshot frozen/dosis y restoreZIP reales se reutilizan.
027R2 NO se aceptó como mecanismo de cola: tres probes asesores fallaron.
No se atribuyen esas regresiones locales al APK público1.23.
029 repara sólo active_session_store: cola FIFO de snapshots capturados,
prep→callbackrestore→rollback completos dentro de una exclusión, saneo al
escribir y sets de identidades protegidas/retiradas. No coalescer fotos a través
de la barrera; último guardado eventual permanece y save/load ordinarios siguen
tolerantes. Puede escribir más snapshots intermedios que el coalescing previo.
El callback restore no debe encolar y esperar otra operación del mismo store.
Marcadores de callbacks viven sólo en el proceso: no migración/schema/metadata nueva.

Lectura crítica reconoce ausencia real y rechaza error I/O o archivo no
interpretable antes de cambiar DB. Rollback restaura bytes y protecciones
previas; fallo de recuperación mantiene desvinculación conservadora y avisa.
Nueva sesión mantiene su vínculo; clear/save sin restore no está prohibido.

## Evidencia local

SDK3.22/Dart3.4, PHP C:/xampp/php/php.exe, SQLitehost real, filesystem temporal
ficticio. Fuente de gateway contract2 pinned e íntegra; proveedor/no datos
personales/credenciales, ninguna llamada IA/red ni modificación backend.

[red-queue.txt](029-evidence/red-queue.txt):3probes permanentes contra31b0d0e
fallan exactamente (ID7reaparece, segunda restore borra protección, sesión
antigua pisa nueva). [red-queue-expanded.txt](029-evidence/red-queue-expanded.txt):
5fallos/2controles, añadiendo lecturaI/O y JSON no interpretable que devolvían
éxito antes. Oráculos originales preservados íntegros.
[green-directed.txt](029-evidence/green-directed.txt):44pass/0fallos/0skip,
cola7/crítica8/store4/ZIPUI-reanudar/fotos. Éxito, cancelación, rollback exacto,
preescritura fallida y campos3x6 frente a3x12 verificados.
[analyze.txt](029-evidence/analyze.txt):sin incidencias. Bundle/PythonPASS repetidos.
Suite completa combinada serializada NO quedó verde: véase bloqueo del entorno
debajo. Timeout90s y concurrency1 intactos, PHPinterop obligatorio.

Full1 [full.txt](029-evidence/full.txt), fuente31b0d0e+029 (hashes en
[full1-source.json](029-evidence/full1-source.json)):exit1,957pass/16skip/4fallos
terminales. InteropPHP pasó sin skip. No se borró ni reinterpretó ese rojo.
Dos fallos backup_settings eran fixture sin ActiveSessionStoreProvider real,
dependencia nueva027; se incorpora store temporal sin cambiar oráculos ZIP/DB.
pilot_profile consultaba130 en la fecha fija10oct tras aceptación de fecha real
posterior; [baseline433f64f](029-evidence/pilot-baseline-red.txt) reproduce
exactamente130vsnull. La prueba ahora exige130 enfechaactual y null enalta
anterior, manteniendo7versiones/no duplicación. No se modifica Profile/Goal.
experience usaba SleepLine como ancla pese a que después14h puede estar oculto;
[baseline433f64f](029-evidence/experience-baseline-red.txt) reproduce Noelement432.
Ancla permanente Proteína de la MISMA RingsCard hitTestable prueba montaje antes
de absenceMorning16h; positivoMorning8h,CTA,expansión/díacompleto conservados.
Baseline aislada bajo buildignorado usa blobs433f64f, config y generaciónSchema23
idéntica; sin fullbase ni cambios a fuente producción para arreglar fixtures.

Scope3fixtures adicional autorizado por coordinador después del rojo, no se
debilitaron criterios ni timeouts. [fixture-directed-green.txt](029-evidence/fixture-directed-green.txt):
34pass/0fallos/0skip. [analyze-final.txt](029-evidence/analyze-final.txt):sin incidencias.
Fuente029+fixtures estable commit a1351d3, antes de revisión y full2.

## Bloqueo terminal de full y diagnóstico del entorno

Full2 sobre a1351d3, [full-final.txt](029-evidence/full-final.txt): exit1,
contador reportado952 aprobadas/16capturas omitidas; nueve casos updates_card
terminaron `did not complete`, sin error de aserción de esos casos registrado.
Ese contador parcial y las aprobaciones dirigidas NO acreditan una full verde.
Las dieciséis omisiones siguen siendo capturas opcionales; interopPHP no se omitió.
Fuente/tests no se modificaron después de a1351d3 ni durante la corrida.

Diagnose: mismo archivo updates_card, mismo SDK/timeout90/concurrency1, sin
cambio de fuente, [updates-diagnosis.txt](029-evidence/updates-diagnosis.txt):
Flutter abortó antes de ejecutar con FileSystemException `writeFrom failed`,
dart-flutter-telemetry.log, errno112 «Espacio en disco insuficiente». El
[crash report original](029-evidence/flutter-crash-disk112.txt) conserva comando
y stack AnalyticsImpl/LogHandler. La telemetría medía9545bytes, no era un gran
archivo. C libre fue observado221MiB después del crash y luego0bytes.

Hipótesis distinguidas: H1 falta de espacio (mismo dirigido debería recuperarse
tras liberar capacidad); H2 runner/fuentes (persistiría con capacidad suficiente);
H3 contención del host (presión/timing persistiría independientemente del disco).
Errno112 confirma fallo de espacio en el diagnóstico posterior, pero no demuestra
por sí solo la causa completa de los nueve `did not complete` de full2.
Hace falta el contraste dirigido posterior; no se atribuye un bug de producto
ni se declara solucionado el runner por inferencia.

Tres acciones de limpieza autorizadas y acotadas fueron rechazadas por revisión
automática del tool con razón genérica `blocked by policy`: script recursivo
de cuatro outputs propios ignorados; alternativa literal sólo baseline; y un
solo snapshot build_runner ignorado de25532656bytes sin -Recurse. Se verificaron
rutas absolutas dentro del worktree y ausencia de reparse. **Nada se eliminó**;
no se cambió shell/lenguaje ni se evadió el rechazo. Registro de hechos del tool,
no stdout inventado: [cleanup-review-rejections.json](029-evidence/cleanup-review-rejections.json).

Cierre documental autorizado por heartbeat, separado de pruebas: al iniciar
este cierre se verificaron905203712bytes disponibles (>100MiB, <1GiB), suficientes
para evidencia/Git limitada; ningún Flutter/analyze/full ni limpieza se ejecutó.
Gate **full/formaltesting BLOCKED por entorno**; implementación local y dirigidos
quedan acreditados con sus alcances, no equivalen a validación operacional.

Próximo paso: verificar margen≥1GiB; repetir exactamente dirigido de nueve
updates_card sobre a1351d3 con SDK3.22 y timeout90; sólo si termina correctamente,
ejecutar full serial con PHP real hasta terminal. Preservar negativos, contador
observado y nuevas evidencias; no reducir asserts, omitir casos ni subir timeout.
Supervisor sigue activo por pedido del owner y Claude vigilante debe recibir
acuse tras recuperación; revisión/heartbeat no sustituyen esa verificación.

## Contexto y comprobación del diff

validate-context-library.ps1 -ProjectRoot WORKTREE devuelveexit1/18errores:
exige plantilla inglesa/corefiles nuevos que biblioteca histórica no utiliza.
[Salida actual](029-evidence/context-validator.txt) y
[baseline433f64f](029-evidence/context-validator-baseline.txt) tienen18errores;
no se oculta ni corrige fuera de alcance. INDEX sí enruta a recibos/roadmap y
documentos de tema mantenidos. Migración a biblioteca modular queda pendiente
separada; no equivale a defecto funcional del producto.
`git diff --check 433f64f..a1351d3 -- . ':!docs/context/sessions/026-evidence/**'
':!docs/context/sessions/028-evidence/**'`:exit0; incluye toda fuente/docs/metadatos.
Raw027/029 preservado -text/-diff; raw026/028 conserva whitespace, incluirlo
devuelveexit2 (documentado en recibos026/028). No reescribir raw para verde.

Revisión independiente asesor sobrea1351d3:
[review-independent.txt](029-evidence/review-independent.txt),20pass/0fallos:
cola7+crítica8+ZIPUI5. Fuente/rango revisados antes de full2; ninguna competencia
con otra corrida Flutter. Claude009 también revisó estáticamentea1351d3 sin
bloqueantes nuevos (entrada19:36 en
`C:/My Projects/seguimiento-122-integracion/plans/coordinacion-2026-10-12.md`).
Esa revisión no ejecutó tests/Android y no es aceptación humana.

## Gates

Implementación local y pruebas host; publicación nueva/APK/Android/CI remoto/
teléfono/aceptación humana/precisión y coste IA no evaluados en este pedido.
QA ampliada/teléfono1.23 sigue NOT_EXECUTED_OWNER_DEFERRED. No push, release,
deploy, SDK/lock/versión/esquema nuevos. Backlog/históricos conservados.

Dos mejoras menores quedan pendientes tras revisión estática deClaude009:
- Doble fallo DB+rollback: no reproducido/no evaluado. DatabaseHost conserva
  journal/copia para recuperación al iniciar; puede quedar conexión cerrada o
  estado no operativo hasta reabrir. No se demuestra vínculo contra una base
  ajena; no hay barrera UI explícita aparte del error que pide reiniciar.
- SessionRecoveryException: archivo queda desvinculado conservadoramente,
  pero activeSessionProvider sólo se invalida al éxito y puede conservar snapshot
  antiguo cacheado. Si DB revirtió correctamente, su ID anterior sigue válido;
  no se demuestra vínculo ajeno. Sincronizar esa caché requiere caso de UI
  reproducido antes de ampliar fuente; no se modificóa1351d3 durantefull2.
