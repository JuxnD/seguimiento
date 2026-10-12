# 027 — fotos atómicas y reanudación tras restaurar

Base `433f64f`, rama `JuxnD/027-fotos-reanudacion`, worktree
`C:/My Projects/seguimiento-027-claude`. Sin cambio de SDK, esquema, lock,
versión ni firma. Host Windows (flutter test); no se probó en Android ni con
datos del owner.

## Fotos (`photo_repository.dart`)
- Defecto: `add`/`reclassify`/`delete` borraban el archivo antes del SQL; un
  rollback dejaba la fila apuntando a un archivo inexistente.
- Ahora: archivo nuevo reservado con `create(exclusive: true)` (dos altas del
  mismo milisegundo no se pisan), fila en transacción, y el archivo previo se
  borra solo tras el commit. Si falla, se limpia el archivo nuevo. `delete`
  hace DELETE y luego borra el archivo. `remove/restore/purgeFile` intactos.
- Límite: un crash entre commit y purga deja un archivo huérfano en `fotos/`
  (no hay barrido); nunca una foto referenciada sin archivo.

## Reanudación tras restaurar (revisión 1 sobre fe0b565)
- fe0b565 decidía el vínculo con `_sameDay` (estructura): no prueba procedencia y
  omite dosis/descanso/variante. Se eliminó.
- Mecanismo ahora: `restoreBackupFile` (restore común), solo tras `archive.restore`
  exitoso, llama `ActiveSessionStore.unlinkPlanAfterRestore()`: reescribe el
  snapshot guiado con `planDayId = -1` y nota `recoveredPlanNote`, conservando
  los demás campos (`GuidedSnapshot.unlinkedAfterRestore`, idempotente, sin campos
  nuevos ni SQL), y luego invalida `activeSessionProvider`. Cancelación/rollback no lo tocan.
- `resumeActiveSession`: con guion, usa el congelado y conserva `planDayId` si el
  día existe (reanudación ordinaria); si el día no existe, lo suelta con la nota.
  Legado sin guion y guion ilegible: diálogo "Sesión sin su guion" (sin cambios).
- Límites: restaurar mientras un cronómetro está abierto en pantalla podría
  reescribirlo con el id viejo en su siguiente guardado (no probado; flujo de
  Ajustes no coexiste con el cronómetro). Un snapshot de otro dispositivo/copia
  puesto a mano en disco no se desvincula. Probado en host, no en Android.

## Evidencia (`027-evidence/`, `.log.txt` + `SHA256SUMS.txt`; ver README.md)
- Entrega fe0b565: rojo 10/20 contra 433f64f; verde 20 nuevas + 48 existentes.
- Ronda 1: `test/ui/restored_session_unlink_test.dart` (ZIP real con BackupArchive,
  restoreBackupFile, snapshot releído de disco, resume por UI; mismo id/día/tipo/
  nombres con otra dosis). Rojo REAL en fe0b565 (`planDayId` 2 ≠ -1) solo en el caso
  restaurado; cancelado, rollback y ordinario son controles que pasan antes y después.
  Verde: 24 nuevas, 61 existentes, analyze 0, diff-check 0.
- Fallos intermedios conservados y rotulados (harness vs. producto) en README.md.
- Cambios a pruebas existentes: `release121_flows_test` (guion ilegible conserva
  y pregunta), `backup_disclosure_test` (override del store que restore ahora lee).
