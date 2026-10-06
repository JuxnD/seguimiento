# Respaldo, restauración y actualizaciones

Dos cosas que hacen que la app se pueda usar por años sin perder datos:
poder volver a un respaldo y poder instalar una versión nueva encima.

## Respaldo y restauración

**Exportar** (Ajustes → *Exportar registros y fotos*, desde 1.19): prepara un
ZIP `seguimiento-AAAA-MM-DD-<instante>.zip` con una copia consistente de SQLite
(`VACUUM INTO`), las fotos de progreso y las referencias de ejercicios. Se
comparte a donde el usuario elija (Drive, correo, archivos…). Abrir el menú de
compartir **no demuestra que quedó guardado fuera del teléfono**: hay que
comprobar el archivo en su destino. El ZIP contiene datos y fotos personales,
sin cifrado; se conserva únicamente donde el usuario decide guardarlo.

El paquete lo gestiona [`backup_archive.dart`](../lib/data/backup_archive.dart).
Su formato v1 contiene `manifest.json`, `seguimiento.sqlite` y `fotos/`
(incluye `fotos/ejercicios/`). El manifiesto declara formato, versión, fecha,
esquema SQLite, tamaño en bytes y SHA-256 de cada archivo. La app relee el ZIP
que se va a compartir para verificar los hashes; no exporta `flags.json`,
`sesion-en-curso.json` ni las copias automáticas.

Si la base referencia fotos que **ya faltan en el teléfono**, se declaran en
`missingPhotos`, con `complete: false`. La pantalla dice *Respaldo incompleto*
y exige decidir si se comparte de todos modos: esas fotos no se inventan ni
se consideran recuperables. Restaurar ese paquete también exige confirmación
con el número de fotos faltantes. Un archivo faltante que el manifiesto dice
incluido, o una lista de faltantes que no coincide con la base, se rechaza.

Límites v1: **64 MiB por archivo**, **256 MiB de contenido**, **260 MiB por ZIP**,
**4096 archivos** y **1 MiB de manifiesto** (1 MiB = 1.048.576 bytes).
Se leen/escriben por bloques, en un isolate para el trabajo ZIP. Se rechazan
rutas absolutas o que salgan de `fotos/`, duplicados (también por mayúsculas),
enlaces simbólicos, archivos especiales, ZIP64, paquetes de varios volúmenes,
cifrado y compresión distinta de STORE/DEFLATE. Los límites se comprueban
también al descomprimir: mentir en el tamaño declarado no elude el control.

**Copias automáticas** ([`auto_backup.dart`](../lib/data/auto_backup.dart)):
al abrir la app, si pasaron 7 días desde la última, se hace una copia con el
mismo `VACUUM INTO` en `respaldos/respaldo-AAAA-MM-DD.sqlite`, dentro del
directorio de la app, y se guardan las 4 más recientes. Ajustes las lista y
cada una se puede restaurar con el flujo de abajo. Sirven para deshacer un
error (un borrado, una restauración equivocada, una base dañada), **no** para
cambiar de teléfono: si se pierde el teléfono se pierden con él. Para eso sigue
el exportar a mano. Android puede incluir esa carpeta en su copia de seguridad
en la nube (la app no la desactiva), pero no está verificado y no se debe
contar con ello. **Estas copias automáticas solo contienen registros, sin
fotos**. Para cambiar de teléfono o recuperar las fotos hay que exportar el
ZIP manual y guardarlo fuera del dispositivo.

Si la app no logra arrancar (base dañada, migración fallida), muestra una
pantalla con el error y, si la base alcanzó a abrir, un botón para exportarla
antes de reinstalar.

**Restaurar** (Ajustes → *Restaurar desde un respaldo*): admite ZIP portable y
`.sqlite` antiguos. Primero verifica en una carpeta temporal y después pide
confirmación indicando qué se reemplazará. Un ZIP reemplaza base y fotos; un
SQLite antiguo **solo reemplaza la base y conserva las fotos locales**: no
recupera fotos del dispositivo anterior. Implementación:
[`lib/data/database_host.dart`](../lib/data/database_host.dart).

El orden importa y por eso está así:

1. **Validar antes de tocar nada**: para ZIP se comprueban rutas, inventario,
   tamaños, CRC, SHA-256 y referencias de fotos en la base. La copia SQLite
   se abre en solo lectura y debe
   tener las tablas `profiles`, `sessions`, `meals` y `measurements`, y un
   `user_version` (esquema) que esta app entienda. Un respaldo de una versión
   más nueva se rechaza con ese mensaje, en vez de corromper datos.
   Además, una **copia de prueba** del respaldo se abre con la app (corre las
   migraciones) y se consultan tablas y columnas del esquema, la integridad
   SQLite, claves foráneas y el perfil. Un respaldo de esquema
   16 sin `foods` pasaba la validación por tablas mínimas, borraba la copia
   previa y fallaba después (auditoría del 5 oct, 1.17.0).
2. **Copia de seguridad** de la base actual en `seguimiento.sqlite.pre-restore`,
   hecha con `VACUUM INTO` antes de cerrar la conexión. Un diario local
   `seguimiento.sqlite.restore-state.json` se escribe antes de reemplazar nada.
3. Cerrar la conexión, **borrar `-wal` y `-shm`** (pertenecen al archivo viejo;
   mezclarlos con la base restaurada la corrompe). Para ZIP se mueve la carpeta
   de fotos anterior a `seguimiento.sqlite.pre-restore-fotos`, se instala la
   carpeta verificada y se copia el respaldo SQLite encima.
4. Reabrir y consultar la estructura completa. Si algo falla, **rollback**:
   vuelven la base y las fotos anteriores. Si tampoco se puede revertir por un
   problema de disco, el error lo declara y se conservan las copias previas.
5. Se confirma el diario y después se limpian las copias previas. Si Android
   cierra el proceso a mitad, la próxima apertura recupera el estado anterior
   cuando no se había confirmado, o termina la limpieza del estado confirmado.
   La sustitución de varios archivos no es una transacción del filesystem:
   su coherencia depende del staging, el diario y la reversión conjunta.

Después de intentar el reemplazo, **salga bien o mal**, `databaseGenerationProvider`
cambia y Riverpod recrea repositorios y streams: la app muestra los datos
nuevos sin reiniciarse, y un rollback no deja nada apuntando a la conexión
cerrada. La tarjeta de Perfil también se recrea.

Pruebas: [`test/data/restore_test.dart`](../test/data/restore_test.dart) cubre
restaurar, descartar lo posterior, archivo basura, base ajena, inexistente y
el rollback cuando la base restaurada no abre y el respaldo al que le falta
una tabla;
[`test/data/auto_backup_test.dart`](../test/data/auto_backup_test.dart) cubre la
frecuencia, la rotación y que una copia automática se pueda restaurar.
[`test/data/backup_archive_test.dart`](../test/data/backup_archive_test.dart)
cruza A→ZIP→B con SQLite y archivos reales sintéticos, relee registros y hashes
de ambas clases de fotos, comprueba rechazos sin alterar B, una falla tardía con
reversión y recuperación del diario después de un cierre simulado.
[`test/data/backup_settings_test.dart`](../test/data/backup_settings_test.dart)
recorre Ajustes, selección del ZIP, confirmación/cancelación, restauración y
renovación de providers; solo sustituye el selector del sistema.

**Validación operacional pendiente:** en dos instalaciones Android de prueba,
exportar a un proveedor de archivos, comprobar allí el ZIP, importarlo y
comparar registros y fotos. También probar cierre del proceso durante la
restauración. Las pruebas locales sintéticas no prueban el proveedor de
archivos ni la aceptación en el teléfono de uso diario.

## Actualizaciones por GitHub Releases

La app consulta `https://api.github.com/repos/<usuario>/<repo>/releases/latest`,
compara la etiqueta con su propia versión y, si hay una más nueva, ofrece
abrir la descarga del APK. **No instala nada sola**: la instalación la haces tú.

- Servicio: [`lib/data/update_service.dart`](../lib/data/update_service.dart)
- Comparación de versiones: [`lib/domain/version.dart`](../lib/domain/version.dart)
- UI: tarjeta en Ajustes y aviso en Hoy
  ([`updates_card.dart`](../lib/features/settings/updates_card.dart))
- Repositorio configurado: [`lib/config.dart`](../lib/config.dart), sobreescribible
  con `--dart-define=GITHUB_REPO=usuario/repo` (el workflow lo pasa solo)

Si el repositorio no está configurado o la consulta falla, la tarjeta lo dice y
la app sigue funcionando: el chequeo nunca bloquea nada.

### Una sola "Seguimiento" en recientes (§16.13, 5 oct 2026)

Al actualizar desde *Ajustes → Descargar APK* quedaban dos tarjetas de la app
en recientes (una en Ajustes, otra en Hoy): el navegador y luego el
instalador se abrían dentro de la tarea de la app, y el "Abrir" del final
creaba otra porque `MainActivity` tenía `taskAffinity=""`. Ahora:

- *Descargar APK* va por el canal `seguimiento/sistema`
  (`openApkDownload`, en `MainActivity.kt`): abre la descarga con
  `FLAG_ACTIVITY_NEW_TASK` y cierra la tarea de la app con
  `finishAndRemoveTask()`. La tarjeta avisa que la app se cierra. Si el canal
  falla, se abre con url_launcher como antes. La app sigue sin instalar nada
  (ADR 0006): no hay `REQUEST_INSTALL_PACKAGES` ni FileProvider.
- `MainActivity` es `singleTask` y con la afinidad por defecto: launcher,
  avisos y el "Abrir" del instalador reutilizan la misma tarea. Lo que llegue
  con la app abierta entra por `onNewIntent`.
- Guarda: `test/app/android_manifest_test.dart`. El flujo completo (descargar,
  instalar, "Abrir", mirar recientes) solo se comprueba en un teléfono.

## La firma: lo único que no se puede improvisar

Android **solo deja actualizar una app si el APK nuevo está firmado con la misma
llave** que el instalado. Si cambias de llave, la instalación falla con "app no
instalada" y la única salida es desinstalar, lo que borra los datos.

Por eso:

- Todas las releases se firman con la misma llave (`android/seguimiento.jks`).
- La llave y sus contraseñas **nunca** van al repositorio (`.gitignore` ya las
  excluye). En CI viven como secrets.
- El APK que compilas en local sin `key.properties` usa la llave de *debug*: sirve
  para probar, pero **no** se puede actualizar con uno de CI. Cuando pases al
  sistema de releases, desinstala el APK de prueba (exporta el respaldo antes) e
  instala el de la primera release.

### Crear la llave (una sola vez)

```powershell
powershell -ExecutionPolicy Bypass -File tool\crear-llave-firma.ps1
```

`keytool` te pedirá las contraseñas. Guarda la llave y las contraseñas en tu
gestor de contraseñas; si las pierdes, pierdes la ruta de actualización.

### Secrets del repositorio

En GitHub → *Settings* → *Secrets and variables* → *Actions*:

| Secret | Qué es |
|---|---|
| `KEYSTORE_BASE64` | La llave en base64: `[Convert]::ToBase64String([IO.File]::ReadAllBytes('android\seguimiento.jks')) \| Set-Clipboard` |
| `KEYSTORE_PASSWORD` | Contraseña del almacén |
| `KEY_ALIAS` | `seguimiento` |
| `KEY_PASSWORD` | Contraseña de la llave |

### La llave de las releases

Hasta la 1.6.0 el repositorio no tenía secrets de firma: `release.yml` fallaba en
"Preparar llave de firma" y todas las releases (1.0.1 a 1.6.0) se subieron **a
mano**, con un APK compilado en el equipo de desarrollo sin `key.properties`, es
decir, **firmado con la llave debug de ese equipo** (`~/.android/debug.keystore`,
SHA-256 `6F:83:9C:41:…:AC:13:3E:D7`).

Decisión (24 sep 2026): esa llave debug **es** la llave de las releases, para no
romper la ruta de actualización de lo ya instalado. Se subió como secret:

| Secret | Valor |
|---|---|
| `KEYSTORE_BASE64` | `debug.keystore` en base64 |
| `KEYSTORE_PASSWORD` | `android` |
| `KEY_ALIAS` | `androiddebugkey` |
| `KEY_PASSWORD` | `android` |

Desde la 1.6.1 CI firma y publica solo. Verificado el 24 sep 2026: el APK que
publicó CI para la 1.6.1 tiene la misma huella que las releases manuales
(`keytool -printcert -jarfile`) y `versionCode` 10, así que se instala encima.

Consecuencias:

- `debug.keystore` de ese equipo **es la llave de release**: hay que respaldarlo
  fuera del equipo. Perderlo corta la ruta de actualización (habría que
  exportar, desinstalar, instalar y restaurar; las fotos no viajan).
- Su contraseña es la pública de Android: la protección real es que el archivo
  no salga del equipo ni de los secrets. No se sube al repositorio.
- Para subir los secrets desde `cmd` (sin salto de línea al final, que rompe el
  `base64 -d` del runner):
  `powershell -NoProfile -Command "$b = [Convert]::ToBase64String([IO.File]::ReadAllBytes($env:USERPROFILE + '\.android\debug.keystore')); gh secret set KEYSTORE_BASE64 -R JuxnD/seguimiento --body $b"`

### Publicar una versión

1. Subir la versión en `pubspec.yaml` (`version: 1.1.0+2`; el `+N` siempre crece).
2. Commit y `git push`.
3. Etiquetar y empujar:

```bash
git tag v1.1.0 && git push origin v1.1.0
```

El workflow [`release.yml`](../.github/workflows/release.yml) analiza, prueba,
verifica que la etiqueta coincida con `pubspec.yaml`, compila el APK firmado y
lo publica en la release como `seguimiento-v1.1.0.apk`. La app instalada lo
detecta en el siguiente chequeo.

El workflow se dispara con cualquier etiqueta `v*` o a mano
(`workflow_dispatch`). Además de lo anterior genera el código de drift y borra
la llave del runner al terminar, pase lo que pase. Corre en Java 17.

[`ci.yml`](../.github/workflows/ci.yml) corre en cada push a `main` y en los PR:
genera código, comprueba el manifiesto de Android (permisos y receivers que
ninguna prueba de Dart detecta), analiza, prueba (incluidas las de pantalla) y
compila un APK de debug, para que un cambio de Gradle o de un plugin nativo no
se descubra recién al etiquetar.

## Qué sigue siendo manual

- Instalar el APK (Android pide permitir "instalar apps de esta fuente").
- Decidir cuándo actualizar: la app avisa, no obliga.
- Hacer el respaldo antes de actualizar o restaurar. La app lo recuerda, pero
  no lo hace por ti.
