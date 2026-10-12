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

## Reanudación tras restaurar (`training_screen.dart`)
- Con `effectiveDay`: se retoma siempre con el guion congelado (dosis, marcas,
  índice, calentamiento). El `planDayId` se conserva solo si en la base actual
  el día es el mismo por estructura (`_sameDay`: weekday, tipo y ejercicios del
  plan, en orden, contenidos en el guion; el guion puede traer de más). Si no,
  se retoma sin plan (`-1`) y la nota de contexto dice "Recuperada tras
  restaurar…".
- Sin `effectiveDay` (legado 1.20): automático solo si lo ya hecho cabe en el día
  del id; si no hay con qué comprobarlo (p. ej. nada hecho) o el día no existe,
  diálogo "Sesión sin su guion": Dejarla pendiente / Descartarla / (si hay día)
  Retomar con ese día (sin vincular al plan). Guion ilegible: mismo diálogo.
  Nunca se borra el archivo sin elegir "Descartarla".
- Límite: `_sameDay` no prueba procedencia; un día de otra base con la misma
  estructura se vincula (efecto: evidencia de progresión idéntica en forma).
- Contrato cambiado en `release121_flows_test`: el guion malformado ya no se
  descarta en silencio y el legado sin lo hecho pide confirmación.

## Evidencia (`027-evidence/`, SHA256SUMS.txt)
- `red-433f64f.log`: pruebas nuevas contra el producto de la base: 10 fallos
  (3 fotos: INSERT/UPDATE/DELETE fallidos pierden foto; 7 reanudación).
- `green-new.log`: 20 pruebas nuevas pasan. `green-existing.log`: 48 existentes
  (fotos, técnica, active_session, warmup, release121, backup, light) pasan.
- `analyze.log`: sin incidencias. `git diff --check`: 0.
- Pruebas de reanudación usan SQLite real + archivo de snapshot real + callerUI
  `resumeActiveSession`; no hay restauración ZIP completa (límite: la base
  "restaurada" es una base con otro plan).
