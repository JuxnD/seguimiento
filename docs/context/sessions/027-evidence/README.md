# Evidencia 027 (texto, versionada)

`*.log` quedan ignorados por git; aquí van copias `.log.txt` con hash en `SHA256SUMS.txt`.

## historical-pre-fe0b565/ (copias del asesor, sin tocar)
Corridas anteriores a fe0b565, borradas del disco por un `rm -f` y recuperadas de
`seguimiento-122-integracion/plans/027-historical-evidence/`:
- `photos-red.log.txt` / `resume-red.log.txt`: primeras corridas rojas contra la base. Incluyen fallos de
  EXPECTATIVA de la prueba (p. ej. `anyOf` con listas, aserción de bytes) además de pérdida real de foto;
  no todo rojo ahí es bug de producto.
- `photos-green.log.txt` / `resume-green.log.txt`: intentos verdes intermedios (algunos aún con la expectativa mal escrita).
- `final-new.log.txt` / `final-existing.log.txt`: corridas dirigidas previas a la ronda 1.

## Entrega fe0b565
`red-433f64f.log.txt`, `green-new.log.txt`, `green-existing.log.txt`, `analyze.log.txt`.

## Ronda 1 (prefijo r1-)
- `r1-harness-failure-alta-invalida.log.txt`: la prueba nueva fallaba por HARNESS (respaldo sin perfil válido:
  "alta inválida"); no es bug de producto.
- `r1-harness-failure-snack-esperado.log.txt`: el control de la prueba tomaba el aviso de éxito como error; harness.
- `r1-red-fe0b565.log.txt`: rojo REAL contra fe0b565: la restauración exitosa deja `planDayId` 2 (mismo id,
  mismo día/tipo/nombres, otra dosis) en vez de -1. Los casos cancelado/rollback/ordinario pasan (controles).
- `r1-backup-disclosure-rerun.log.txt`: fallo real causado por mi cambio (restore lee el store; esa prueba no lo
  proveía); corregido con un override en la prueba. `r1-backup-disclosure-fixed.log.txt`: verde.
- `r1-green-unlink.log.txt`, `r1-green-new.log.txt` (24), `r1-green-existing.log.txt` (61), `r1-analyze.log.txt`.

## Ronda 2 (prefijo r2-)
Evidencia en bytes exactos: `.gitattributes` fija `-text -diff` para esta carpeta; `SHA256SUMS.txt` coincide con
`git show HEAD:<ruta>` y con la copia de trabajo.
- `r2-red-8b1cac5.log.txt`: rojo REAL contra 8b1cac5 (producto de la ronda 1): (a) restaurado: un guardado tardío
  de la misma sesión repone el id (`Expected (-1, 4)`, `Actual (2, 4)`); (b) tmp bloqueado: la restauración se
  ejecuta igual (la generación pasa a 1, la base se reemplazó), por eso la espera de "restauración terminada" con
  generación 0 no se cumple.
- `r2-red-8b1cac5-store-api-ausente.log.txt`: la prueba de bajo nivel no compila en 8b1cac5 (la API
  `protectedRestore` no existe); no es un rojo de comportamiento.
- `r2-red-8b1cac5-test-intermedio.log.txt`: mismo rojo con una versión previa de la prueba (índice+1).
- `r2-harness-failure-sed-late.log.txt`: fallo de HARNESS, un `sed` mío rompió las declaraciones `late`.
- `r2-harness-failure-green-intermedio.log.txt`: intermedio con expectativas de tipos mal escritas y un cambio de
  índice que dejaba el cronómetro en descanso (finder offstage); harness, no producto.
- `r2-green-new.log.txt` (33 pruebas), `r2-green-existing.log.txt`, `r2-analyze.log.txt`.
