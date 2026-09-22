# Respaldo, restauración y actualizaciones

Dos cosas que hacen que la app se pueda usar por años sin perder datos:
poder volver a un respaldo y poder instalar una versión nueva encima.

## Respaldo y restauración

**Exportar** (Ajustes → *Exportar base de datos*): `VACUUM INTO` produce una
copia consistente aunque el WAL tenga escrituras pendientes; luego se comparte
el archivo `seguimiento-AAAA-MM-DD.sqlite` a donde quieras (Drive, correo…).

**Restaurar** (Ajustes → *Restaurar desde un respaldo*): eliges el archivo,
confirmas y la app reemplaza la base. Implementación:
[`lib/data/database_host.dart`](../lib/data/database_host.dart).

El orden importa y por eso está así:

1. **Validar antes de tocar nada**: el archivo se abre en solo lectura y debe
   tener las tablas `profiles`, `sessions`, `meals` y `measurements`, y un
   `user_version` (esquema) que esta app entienda. Un respaldo de una versión
   más nueva se rechaza con ese mensaje, en vez de corromper datos.
2. **Copia de seguridad** de la base actual en `seguimiento.sqlite.pre-restore`.
3. Cerrar la conexión, **borrar `-wal` y `-shm`** (pertenecen al archivo viejo;
   mezclarlos con la base restaurada la corrompe) y copiar el respaldo encima.
4. Reabrir y hacer una consulta real. Si algo falla, **rollback**: vuelve la
   base anterior y el error se muestra tal cual.
5. Al terminar bien, se borra la copia de seguridad.

Después de restaurar, `databaseGenerationProvider` cambia y Riverpod recrea
repositorios y streams: la app muestra los datos nuevos sin reiniciarse.

Pruebas: [`test/data/restore_test.dart`](../test/data/restore_test.dart) cubre
restaurar, descartar lo posterior, archivo basura, base ajena e inexistente.

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

[`ci.yml`](../.github/workflows/ci.yml) corre análisis y pruebas en cada push a
`main` y en los PR; en Linux también corren las pruebas de UI que en Windows
quedan saltadas.

## Qué sigue siendo manual

- Instalar el APK (Android pide permitir "instalar apps de esta fuente").
- Decidir cuándo actualizar: la app avisa, no obliga.
- Hacer el respaldo antes de actualizar o restaurar. La app lo recuerda, pero
  no lo hace por ti.
