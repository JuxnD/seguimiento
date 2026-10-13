# Checkpoint25: actualización y ZIP24 genuinos

Probe aislado sobre c518479; código de aplicación25 sin borradores de034.
Fixture construido en otro checkout aislado desde c47a94af usando su verdadero
AppDatabase24, generated24 con inputs verificados, SQL sintético y exportador
BackupArchive24. No se fabricó24 modificando PRAGMA sobre tablas25.

Fixture aceptado: `test/fixtures/schema24_034_ready`. Manifiesto pinned SHA256
8279216d74527852dce64a317f088fb176bffe262aff2806b735f56fe223a747.
SQLite SHA be64f54618c36c22df40fe43910ed3919670849eb15374a6b205d2ecd6ee948c;
ZIP SHA13e644637d6df8242bab03c796e2d7e7240298bc11b630da9c985dad0a14b849.
La cápsula y su manifiesto se conservan inmutables, también los IDs, secuencias,
tipos y todas las columnas originales. La comparación incluye tablas vacías.

Tres controles terminales PASS: fresh25, actualización24→25 y reapertura con
mutación de un recordatorio detectada; ZIP24→25, reapertura y segundo restore,
sin cambios de filas originales ni flags locales. Todas las columnas25 quedan
NULL y las nuevas tablas vacías; no backfill ni vínculo retrospectivo por texto.
Las fuentes25 y generated permanecieron congeladas. Pub offline no cambió lock.
Receipt tests20261013T172348559-52284-3be894685feb4f7bb7a7af3383a4f8df;
analyze final0issues/exit0 receipt20261013T172403274-25376-a23e5933159b431b9bd94b5d7dcc2eaf.

Se preserva `schema24_034` y `upgrade25-tests.txt` FAILED2PASS/1FAIL: el primer
fixture mezcló alta new/pending con registros. El ZIP fue rechazado por el
guard22 correcto. No se relajó el guard ni se cambió producción. Un NUEVO
fixture usa el helper histórico asExistingUser(goals:false) y otro destino,
sin sobrescribir el anterior. También se conserva análisis con2infos previo
al tipado explícito del lector de manifiesto. Avisos debug por conexiones de
trial/restauración se preservan; no son errores ni fueron silenciados.

Builder exacto archivado en034-probe-evidence/schema24-builder.dart.txt para
repetir en sourcec47. No ejecutar ese builder con25: exige24 antes de emitir.
Este checkpoint permite revisión independiente para040. No cierre completo034:
faltan plantilla/agenda/UI/benchmarks/rodilla y restauración integral029 en el
candidato final, además de035/037. No APK, publicación, teléfono ni IA real.
