# 034: evidencia funcional parcial, 13 octubre 2026

Este documento registra un checkpoint de implementación, no cierre de Plan034.

## Identidad
Worktree `C:/My Projects/seguimiento-034-plan-v32-tests`, rama `JuxnD/034-plan-v32-tests`, base de contrato25 `85f92c6542138a06d2dd94ce74fbed7c9424b8be`. Esquema25 firmado/aceptado como interfaz para040; fuente principal todavía contiene cambios sin revisar de034. No copiarla como entrega final.

## Comportamiento demostrado
- Guardar dos intentos de la misma ronda y fecha preserva ambos resultados y sesiones auxiliares independientes.
- Ocho controles nuevos SQLite fallaron funcionalmente en c2c2f3b: última sesión con calidad desconocida, cualquier serie split/toFailure (primera/intermedia/última), y último target con sólo ejercicio auxiliar de criterio. Los fallos fueron Expected0/Actual2–3, con harness operativo.
- Los mismos ocho controles pasan en candidato034: invalidez permanece para toda la sesión, y prescripción por epoch mantiene el intento parcial sin confundir hollow ajeno a la escalera.
- Total12 pruebas dirigidas PASS/0skip incluye append, fresh25 y cápsula genuina24→25/ZIP24. Analyze de lib+dos archivos de tests0issues. No representa analyzeall ni suite completa.

Raw/recibos están en `034-evidence/`. Baseline `ladder-functional-red.txt`; candidato `functional12-tests.txt`. Recibos181032136,181542466,181607830,181615768 en plans/lease-receipts compartido. Manifiesto candidato después de corrección mecánica `postfix-functional-packet.json`, SHA256 B24F2A1221DF794C55901DB3F38F0D169EC3B251AAFE87ADA63B8BC5227EADE7. Los avisos debug multipleDB de trialRestore permanecen en raw; no fueron ocultados.

## Contratos implementados en preparación, aún no validados
- `_seriesSides:v1:` conserva I/D/null real por ejercicio/setIndex, sin inferir lados de la posición de una serie.
- `_ladderPrescription:v1:` declara mantenimiento reducido separado del resultado observado. Sólo prescripción completa de calidad conocida puede ser neutral; edición manual de series invalida proof correspondiente. No inferir mantenimiento del mero conteo de dos series.
- Core de evidencia de tests agrupa attemptId/protocol/item, fecha y condiciones conocidas; ambos lados deben pertenecer al mismo intento y condición. Radar conserva cada intento y calcula comparación sólo en la línea base compatible; legado desconocido sigue visible sin fabricar porcentaje.
- Thin seam visual autorizado: patch598^→7df75a3 sólo dos archivos UI de035 y fixture API. Ningún asset/generator/fase2 copiado. `physicalVariantKey` desconocida produce ausencia explícita, nunca sustituye la postura base. No declarar once variantes visuales completadas hasta entrega035 validada.

## Pendientes reales antes de cierre
Pruebas adicionales de ciclo edit/delete/sessionId, mantenimiento SQL/manualedit, codecs/lados, benchmarks/rodilla, condiciones/baselines, propósito de toda la semana y API física están preparadas pero requieren ejecución. Completar agenda efectiva común, dosis basadas en evidencia, progresiones nuevas, cobertura de todas las superficies/guías/contextos, migraciones23→24→25, ZIP25 y ActiveSession029 enlazado/desenlazado. Integrar040/039/035 sólo cuando root entregue SHAs revisados. Cierre034 requiere revisión root R1 sobre candidato limpio/fijo y evidencia proporcional, no sólo generación25 ni estas12 pruebas.

## Actualización material de 13 octubre: validación parcial posterior
El paquete de 27 controles terminó con 26 PASS y un fallo real en el inventario de propósitos de ejercicios heredados. Se añadieron guías comunes para esos cuatro nombres; el inventario y dos guardas SQLite de tablas personales nuevas pasaron después (3 PASS/0skip). El rojo del inventario permanece en evidence27-tests.txt; no se filtraron ejercicios para obtener verde.

Seis regresiones existentes produjeron 34 PASS y 23 FAIL/0skip: 22 esperaban elegibilidad de intentos sin condiciones/identidad conocida y una llamaba limpia a una sesión cuya calidad era null. Con aceptación explícita del contrato por root, los fixtures positivos ahora registran condiciones y calidad ficticias conocidas; las aserciones numéricas se conservaron y nuevos negativos mantienen el legado observable sin dosis o porcentajes. El retest sigue pendiente.

Las siete familias accesorias reutilizan el motor CoreLadder. Las cuatro prescripciones de mantenimiento reducidas son explícitas; la variante física depende del nivel/prescripción, jamás de inferir repeticiones. El equipo de anillas requiere confirmación y el nivel histórico no se borra al retirar disponibilidad. La respuesta del Aquiles sólo puede confirmarse desde la mañana siguiente. Hay 18 IDs distintos reales de Activa/Suelta; 17 era el número de solicitudes nuevas de figuras de032.

El diagnóstico SDK del freeze9B39 aplicó formato a65 archivos (33 cambiaron) y once correcciones mecánicas en cinco fuentes. Analyze encontró dos errores de nulabilidad de WorkStep en alarm chips, cinco warnings y cuatro infos. No se ejecutaron tests después de ese analyze. Se liberó la ventana y se corrigieron estáticamente; el siguiente candidato es accessories-fixes-freeze.json SHA2566BF957248FFDF0E166D7EF4D40230C3E54A1EE37CB42DCB16F048D195F42C61C, HEAD4b23a6f, sin drift al último chequeo. No supone aprobación de034 ni validación de esas adiciones.
## Checkpoint parcial para dividir ejecución, 20:31 UTC
El paquete43 no terminó: analyze de lib+24 archivos de tests dio0issues, stairs3 y observations4 PASS. El primer UI de equipo falló al releer flag (NULL tras tap), luego el teardown no progresó por más de90s; se canceló sólo el árbol propio del runner ligado al token. Receipt203106991 exit-1; listado de procesos en observation-own-cancel-processes.json. Los otros36 controles no se consideran ejecutados por esta ventana. El origen UI→NativeIO/FakeAsync está bajo diagnóstico; no cambiar aserciones ni timeout para fabricar verde.

Cambios respaldados por esos7 controles: escaleras0/NULL tienen procedencia propia y preservan severidad Rodilla legada; fecha explícita opcional achillesCheckedOn estricta, sin fecha legacy7 no acredita criterio Sóleo; fecha futura no acredita advisor ni writer; alarmas manuales transaccionales al guardar, idempotentes por sesión entre fechas, no se borran al editar; snapshot linked/unlinked conserva payloads7/8 sin reescribirlos. La UI de equipo, mañana y cancelación está implementada pero su validación queda pendiente.

Este commit de checkpoint es parcial y no una entrega R1 de034. Permite ejecutar un slice independiente de lectura/reportes/agenda desde una base fija. Permanecen abiertos: diagnóstico UIequipo y resto43, dosificación/plan completo, TestMode frente a rodilla/restOnly, aviso de tres días, benchmark agenda y desplazamiento, agenda tipada visible/recordatorios/reporte, dosis13 con condiciones conocidas, migraciones/cápsulas y validación completa37. Assets/render035 no se copiaron; 039/040/036 sólo se integran por SHAs aprobados en037.