# ADR0018 · Arranque de marca y respaldo Android

Fecha:10-oct-2026. Estado: decisión autorizada para candidata local016;
validación de APK/manifiesto fusionado/dispositivo pendiente.

## Contexto y autoridades

Base `c04b2a9` (integración122 aprobada, esquema21).013 fija la S naranja
`#F08A34`, zona segura y fondo`#0B0806`;012 fija divulgación de IA, archivo sin
cifrar y licencia fuera deZIP. BackupArchive/DatabaseHost siguen siendo autoridad
para exportar, restaurar y conservar datos. Kotlin/AiCredentialsBridge conserva
activación cifrada en noBackupFilesDir; no se modifica.

El launch antiguo blanco/default y NormalTheme no correspondían al fondoFlutter.
Manifest no fijaba backup: las bases, fotos y conversaciones podían ser elegibles
para los mecanismos automáticos del sistema. Eso no demuestra qué hizo el
teléfono del owner.

## Decisión

- Reusar el foreground013 existente:108dp cuadrado, centrado y dependiente de
  densidad en legacy; atributo nativo31 para el icono. Mismo fondo para launch,
  transición y modo noche. No Activity, plugin, animación ni espera artificial.
- Configurar `allowBackup=false`, reglas legacy y reglas31+ enlazadas desde
  Manifest. Excluir recursivamente los nueve dominios admitidos en cloud yD2D.
  Ningún modo omitido/vacío: no se trata como exclusión.
- Mantener ZIP manual y copias locales, con divulgación y confirmación012.
  Ajustes describe configuración e indica usar ZIP. No elimina copias previas,
  controla servicios externos ni promete comportamiento universal del fabricante.
- No adoptar API/iOS nueva, SDK, cambio de firma, esquema o credencial.

Según la [documentación de Auto Backup](https://developer.android.com/identity/data/autobackup),
allowBackup puede no bastar paraD2D31+ en algunos fabricantes; los modos sin
reglas permiten datos. La [documentación de splash](https://developer.android.com/develop/ui/views/launch/splash-screen)
permite atributos nativos y recursos alternos31. Se verificaron además atributos
en resources del SDK31 local. Consulta10-oct; no se añaden APIs36.1/iOS.

## Consecuencias y gates

El traslado previsto por la app usa ZIP revisado por el usuario. Parser y
mutantes prueban configuración fuente, referencias y30PNG intactos; pruebas UI
cruzan la divulgación y restauración real. No prueban aplicación de las reglas
por Android/OEM.

Antes de distribuir: comprobar Manifest fusionado y recursos del APK exacto,
arranque frío/transición en día/noche y transferencia/backup en QA sintético.
El responsable de release conserva esos gates; datos existentes y aceptación
del owner no se heredan de estos verdes locales.

## Compatibilidad de lint y entrega personal 1.23 (10 de octubre)

La compilación real con el AGP fijado reportó doce errores FullBackupContent:
su enumeración omitía device_root/device_file/device_database/device_sharedpref.
Los cuatro son válidos en ambos formatos según la documentación oficial citada.
Se conserva EXACTAMENTE la política de nueve dominios. Sólo esos doce excludes
llevan tools:ignore=FullBackupContent; no hay baseline global, abortOnError ni
cambio de SDK, AGP o timeout. LintVital sigue activo para el resto. El verificador
estricto y sus quince pruebas pasan; el rebuild real también pasa. El APK leído
mantiene nueve excludes legacy, nueve cloud y nueve device-transfer, además de
allowBackup=false y las dos referencias del Manifest.

El owner autorizó publicar esta entrega personal y probarla él en su teléfono.
La matriz ampliada de arranque/transporte/Android se registra como
NOT_EXECUTED_OWNER_DEFERRED; no es validación Android/OEM ni aceptación del teléfono.
Se mantienen como gates mínimos obligatorios la conservación offline, análisis,
compilación, identidad/firma del APK y todos los tests de CI/release.
