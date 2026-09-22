# Crea la llave con la que se firman TODAS las releases.
#
#   powershell -ExecutionPolicy Bypass -File tool\crear-llave-firma.ps1
#
# Android solo permite actualizar una app si la firma es la misma. Si pierdes
# esta llave, la única salida es desinstalar la app (y perder los datos que no
# estén respaldados). Guárdala fuera del repositorio y haz una copia.
#
# El script NO inventa contraseñas: keytool te las pide a ti.

$ErrorActionPreference = 'Stop'

$keystore = Join-Path (Split-Path $PSScriptRoot -Parent) 'android\seguimiento.jks'
if (Test-Path $keystore) {
    Write-Host "Ya existe $keystore. Si creas otra, las apps firmadas con la anterior no se podrán actualizar."
    $r = Read-Host 'Escribe SOBREESCRIBIR para continuar'
    if ($r -ne 'SOBREESCRIBIR') { Write-Host 'Cancelado.'; exit 1 }
    Remove-Item $keystore
}

$keytool = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
if (-not (Test-Path $keytool)) { $keytool = 'keytool' }

& $keytool -genkeypair -v `
    -keystore $keystore `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -alias seguimiento

if ($LASTEXITCODE -ne 0) { Write-Error 'keytool falló'; exit 1 }

Write-Host ''
Write-Host "Llave creada: $keystore"
Write-Host ''
Write-Host 'Siguiente paso, firmar en local:'
Write-Host '  Crea android\key.properties con:'
Write-Host '    storeFile=seguimiento.jks'
Write-Host '    storePassword=<la que pusiste>'
Write-Host '    keyAlias=seguimiento'
Write-Host '    keyPassword=<la de la llave>'
Write-Host ''
Write-Host 'Siguiente paso, firmar en GitHub Actions. Copia el texto base64 de la llave:'
Write-Host "  [Convert]::ToBase64String([IO.File]::ReadAllBytes('$keystore')) | Set-Clipboard"
Write-Host '  y pégalo en el secret KEYSTORE_BASE64 del repositorio.'
Write-Host '  Añade también KEYSTORE_PASSWORD, KEY_ALIAS y KEY_PASSWORD.'
Write-Host ''
Write-Host 'key.properties y *.jks están en .gitignore: no los subas nunca.'
