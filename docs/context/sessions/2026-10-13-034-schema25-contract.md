# Contrato aditivo25 de034 — checkpoint para040

Base c47a94af (03224+038) más033 b3c4da4 integrado en c2c2f3b.
Declaración25:527a6439d81caad55e823c9831f59794608bdbf2. Sólo tablas y migrador;
no activa planes ni transforma datos históricos.

- SleepLogs: sleepStart/wakeAt ISO fecha-hora local, source y note, todos Text
  nullable. hours conserva0..16. null histórico no supone procedencia ni reloj.
- CustomReminders.origin Text nullable; usuario/plan/ia sólo con evidencia;
  null legado se presenta desconocido.
- FootballGames.weightsComparable Bool nullable: true confirmación explícita
  de ambos pesajes comparables de ese partido; false alterados/despuésdecomer;
  null desconocido. No backfill. fluidMl null continúa desconocido.
- MorningChecks.kneeStairs Int nullable0..10; cero conserva respuesta y null
  incertidumbre. No inferirlo de SorenessLogs.
- PlanExercises.purpose y physicalVariantKey Text nullable. variant A/B intacto.
  Las11 claves físicas acordadas con035 se pasan explícitamente; desconocida
  no resuelve una imagen genérica. Snapshots029 nuevos conservan campos;
  snapshots anteriores omiten campos y siguen compatibles.
- FitnessTestAttempts: id/date/round/part/protocolId/scheme/blockStart nullable,
  sessionId nullable único. FitnessTests attemptId nullable FK y conditions/
  baselineKey nullable. Legado no recibe enlace retrospectivo por texto.
- MobilityBenchmarks: id/date/item/side/value/touches/conditions/blockStart;
  pike admite signedvalue en modelo propio, no cambia validador reps.

Build_runner25 terminal exit0;462outputs generados ignorados. SHA256 generado
59980C598E2D37C6E4B43EFF3FFC5DF70F545D0FA52170A9B4E014DD60CE2ECB.
Fresh25 y append preliminar2PASS (receipt170745896-67176). El append fue rojo
funcional contra c2c2f3b: Expected[5,8]/Actual[8]. Fallo inicial sin SQLitehost
se conserva como fallo de harness y no acredita defecto de producto.

El análisis del árbol034 con borradores detectó7issues (3error/4info), por lo
que no se declara globalverde. Este checkpoint permite revisión aislada de
tablas/contrato para040; no cierre034. Migración23/24 y ZIP/029, coberturaUI,
resto de slices y análisis final siguen pendientes en034/037.
No APK, publicación, teléfono, IA real ni datos personales.
