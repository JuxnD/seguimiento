# Compuerta local de evidencia del piloto

Herramientas preparadas en 012, 9-oct-2026. No recolectan datos, no ejecutan ADB,
no firman ni publican. No están conectadas al workflow todavía. El próximo
candidato integrado requiere runner/QA nativa nuevos. La procedencia de las
capturas es una responsabilidad del operador/runner revisado, no una propiedad
que un JSON pueda certificar.

## Entradas y autoridad

Usar sólo AVD propio y dataset ficticio. No usar teléfono del owner ni otro
emulador abierto. No cambiar paquete/firma. Congelar el manifest de expectativas
desde fixture/versiones fuente antes de capturar el resultado. No construir el
oráculo copiando la salida candidata que se pretende verificar.

`manifest.json` tiene formato `seguimiento-pilot-manifest`, version1, y exige:

- `sourceSha` y `baseSourceSha`: SHA de commit completos, 40 caracteres.
- `apkSha256` y `baseApkSha256`: SHA-256 de APK, 64 caracteres en minúscula.
- `datasetId` no vacío y `syntheticOnly:true`: identidad del lote ficticio.
- `evidenceKind`: `native_capture` para QA real en AVD; `synthetic_fixture` para
  probar la herramienta. Este campo requiere revisión de procedencia.
- `device`: `{serial:"emulator-...", avd:"nombre propio QA"}`.
- `before` y `after`, cada uno con los datos completos descritos abajo.

Cada directorio de captura contiene `seguimiento.sqlite`, `flags.json`,
`sesion-en-curso.json`, `capture.json`, fotos y XML/logs de fases. La captura
SQLite debe ser consistente, sin escrituras/WAL pendientes; extraer un snapshot
consistente, no copiar sólo el archivo principal de una base en escritura.
Antes/durante/después se conserva el mismo identificador del AVD y mismo lote.

### Expectativas por etapa

`database:{schema:20,tables:{nombre:{columns:[...],columnInfo:[...],rows:[[...],...]}}}` exige todas
las tablas de usuario, columnas y filas, no sólo contadores. Ordenar filas por
su JSON (claves ordenadas, Unicode sin escape) y conservar duplicados; BLOB se
representa como `{blobBase64:"..."}`. Valores nulos son nulos. Comparación de
SQLite independiente, read-only, integrity_check=ok. Las tablas internas
`sqlite_%` no forman parte de este contrato. `columnInfo` conserva las filas de
PRAGMA table_info: cid,nombre,tipo,notnull,default,pk. La comparación distingue
booleanos de enteros y rechaza JSON con números no finitos. Nuevas columnas/normalizaciones
permitidas deben figurar explícitamente en el esperado de la migración y su
justificación, sin alterar silenciosamente el baseline.

`photos` es mapa completo ruta relativa→SHA256 dentro de `fotos/`; fotos extra,
faltantes o distintas rechazan. `flags` y `session` son objetos JSON esperados,
no vacíos; el guion congelado/índice/dosis deben estar declarados.

`installed` exige `{package,versionCode,versionName,targetSdk,signatureSha256}`.
Paquete `com.juandiego.seguimiento`, firma idéntica antes/después, versionCode
superior después. Registrar estos datos desde el paquete instalado y logs reales,
no copiarlos únicamente del manifest. Gate contrasta la metadata candidata con
aapt/apksigner y bytes del APK entregable.

`phases`: en before exige sólo `paused`; en after exige `upgraded`, `resumed`,
`reopened`, `backup_restored`. Por fase:

```json
{
  "ui": "reopened.xml",
  "log": "reopened.log",
  "labels": ["etiqueta esperada independiente", "dosis e índice esperados"],
  "logContains": ["resultado esperado de comando"]
}
```

`capture.json` contiene `device`, `installed` y las mismas fases; cada ejecución
declara `ui`, `log`, `exitCode:0` y `command:[ejecutable,argumentos,...]` no vacíos.
Los logs/UI deben existir y contener las expectativas; cero fases omitidas.
UI se lee como XML de UIAutomator, textos y content-desc. Los comandos deben
ser los ejecutados por el runner revisado (instalar -r, pausa, reanudar, cierre
forzado/reapertura, respaldo/restauración), no descripciones inventadas.
La herramienta comprueba la estructura y artefactos declarados; no ejecuta
estos comandos ni demuestra por sí sola que corresponden a un dispositivo.

## Ejecución

Desde la raíz del worktree del candidato, después de capturar el ensayo:

```powershell
python tool/pilot_upgrade_verify.py --manifest build/pilot/manifest.json --before build/pilot/before --after build/pilot/after --receipt build/pilot/upgrade-receipt.json
python tool/pilot_release_gate.py --apk build/app/outputs/flutter-apk/app-release.apk --receipt build/pilot/upgrade-receipt.json --source-sha (git rev-parse HEAD)
```

El verifier escribe `MATCHED_CAPTURE`, no aceptación humana. Registra hashes
del manifest y todos los archivos, schemas, tablas/filas, fuente, APK e identidad.
El recibo debe estar fuera de capturas y no reemplazar el manifest. Un rerun
fallido elimina el recibo solicitado anterior para evitar usar un verde viejo.

El gate exige captura nativa, compara el APK SHA, fuente, recibo contra una nueva
lectura de los artefactos y metadata con aapt y apksigner. Ambas herramientas son
obligatorias; no sustituye firma/versiones por un hash solamente. Se pueden
indicar explícitamente `--aapt <ruta>` y `--apksigner <ruta>`; por defecto busca
PATH o build-tools en ANDROID_SDK_ROOT/ANDROID_HOME/SDK local Android. JAVA_HOME
debe permitir apksigner. Timeout de metadata:30s; fallo/ausencia rechaza.

Sólo `MATCHED_APK_AND_CAPTURE` con exit0 valida este contrato. No autoriza push,
release, tienda, uso clínico ni teléfono del owner. Workflow aún debe exigirlo y
adjuntar el mismo APK/recibo; no recompilar otro APK después del gate.

## Autocontrol y límites

```powershell
python tool/pilot_gate_test.py
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test test/tool/pilot_release_gate_test.dart
```

Fixture estándar reproducible en TemporaryDirectory, SQLite/fotos/XML/logs
ficticios, sin llamadas de modelo, red, ADB o credenciales. Pruebas positivas de
comparación y negativas: byte APK, fuente, firma independiente, firma de upgrade,
recibo, manifest, schemas/columnas/tablas/filas/duplicados, flags, sesión, fotos,
UI, log, fase no ejecutada/ausente, recibo ausente, herramienta metadata ausente.
Los mocks de aapt/apksigner prueban parseo/cableado de argumentos, no un APK real.
El CLI release rechaza `synthetic_fixture` incluso cuando el verifier la acepta.

No hay firma criptográfica del recibo ni atestación de dispositivo. Cambiar sólo
evidenceKind de un fixture no crea evidencia nativa: revisar procedencia del
runner y custodiar manifest/recibo/logs. Un manifest y capturas falsificados
juntos quedan fuera del modelo de autenticidad de esta herramienta. No usar
esta limitación para afirmar un QA que no se ejecutó.

Pendientes antes de gate operacional: collector nativo del APK integrado,
validación independiente de baseline APK, comprobación de cada fase y migración
declarada, conexión al workflow y prueba de que un rechazo impide publicar.
