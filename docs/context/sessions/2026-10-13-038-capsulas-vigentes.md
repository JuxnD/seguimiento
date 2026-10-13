# 038: cápsulas históricas hacia el esquema declarado 24

Implementación suplementaria test/docs, base eb7256f21f9acfc788282d7680f8b5988a5d73aa; rama JuxnD/038-capsulas-vigentes. Producción032 intocable. El owner autorizó completar implementación y validación; el coordinador refinó038 tras contrastar ReminderRepository.ensureDefaults y DatabaseHost.restoreFrom.

## Cambio y criterio independiente

Los tres recorridos de cápsulas18/19/20 declaran destino24 literal. Nunca se usa el PRAGMA observado como expected. SHA pinned, inventario, columnas, filas, multiplicidades, AI, fotos, flags, sesión activa, ZIP y reaperturas originales permanecen.

Antes de restaurar, las11 filas originales de reminders son exactas sin extras. Sólo después de ZIP→restore se esperan esas11 más tres defaults literales: recuperacionManana activo22:00, rutinaManana activo07:15, rutinaNoche activo21:30, todos thresholdnull. No se importan defaults de producción como oráculo. Segundo restore de cada cápsula verifica14 sin duplicados y conserva ajustes heredados. Mutación de minuto del default nuevo y fila extra no autorizada producen Preservation mismatch:reminders; negativos previos de AI/citas/filas/tiempo/escaleras siguen presentes.

## Evidencia terminal preservada

| Archivo en 038-capsulas-evidence | Resultado real |
|---|---|
| 01-pub-offline.txt | exit0; pubspec.lock intacto |
| 02-red-public20-dest23.txt | baseline sin ajuste: Expected23/Actual24, 0PASS/1FAIL, exit1 |
| 03-green-capsulas18-19-20.txt | nombre histórico: FAILED4PASS/3FAIL, exit1; oráculo legacy rechazó tres defaults esperados al restore |
| 03-result-state.json | FAILED explícito; no se presenta el archivo03 como verde |
| 04-format.txt | tres tests formateados, exit0 |
| 05-green-capsulas-refined.txt | siete controles PASS, exit0, SDK3.22/concurrency1/timeout90s |

Los recibosJSON reales del wrapper se conservan junto a raws. La advertencia Drift de múltiples instancias del harness public20 permanece sin ocultar. Final-guards.json confirma30fixtures y162archivoslib idénticos porSHA256 antes/después. El manifest generated documenta copia estable de database.g.dart de032 y comparación completa de inputs: diferencia byte de checkout sóloLF/CRLF, texto normalizado idéntico; no se reescribieron fuentes. No build_runner, full ni repetición119controles.

## Cierre y límites

- Implementación completa del suplemento: tres tests y este recibo; fuente y cápsulas intactas.
- Validación host: siete controles terminales y negativos de preservación observados; reconsulta sin runner propio antes liberar.
- Cierre formal: revisión independiente del coordinador y veredictoR2 de032 pendientes. Integración037/full final y figuras035 son gates separados.

Sin APK, push, publicación, teléfono, IA real ni datos personales. Snapshot038 anterior sigue histórico y no representa este suplemento.