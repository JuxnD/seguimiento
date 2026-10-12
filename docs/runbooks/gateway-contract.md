# Contrato PHP repetible

Interop prueba Dart → PHP real → Dart con transporte proveedor ficticio y
250g/500kcal esperados. No usa licencia real, cuota ni red/proveedor. Paquete
contiene exclusivamente cuatro fuentes PHP y manifest de contrato2; origen
funcional3f4bff14e5d811415860f4a59180ab3af2e1c1e8, revisión HEAD
2dbf55627c5657acd552d4048b3b7a9da365b520 del backend privado.
Archivos derivados quedan locales en esta fase; publicación requiere revisión
de alcance, no está autorizada por este runbook.
La regla aditiva `.gitattributes` conserva bytes exactos del bundle entre hosts;
sin ella un checkout Windows podría convertir LF a CRLF e invalidar hashes.

## Verificación

Desde la raíz de Seguimiento:

```powershell
python -B tool/gateway_contract_verify.py
python -B tool/gateway_contract_test.py
python -B tool/gateway_contract_verify.py --source 'C:\My Projects\control360i-010-estimate'
$env:SEGUIMIENTO_ESTIMATE_PHP='C:\xampp\php\php.exe'
& C:\seguimiento-sdk-3.22.0\flutter\bin\flutter.bat test --no-pub --timeout 90s --concurrency 1 test/data/gateway_estimate_interop_test.dart
```

En Linux, `php` debe estar en PATH (CI/Release instalan php-cli). Python3 también
es obligatorio. No se requieren mbstring/GD/curl para el seam ficticio utilizado:
unicodeLength usa preg_match_all, la imagen/cuota/red no se invocan.
PHP ausente, paquete faltante/alterado/extra/manifiesto inválido FALLAN; no skip.
El test comprueba el bundle incluso con SEGUIMIENTO_ESTIMATE_GATEWAY apuntando
a otro backend. Ese override ejecuta fuentes locales seleccionadas y debe
usarse sólo sobre checkout confiable; no cambia la identidad del bundle.

Negativo reproducible, proceso independiente (debe exit1 e indicar PHP CLI
obligatorio): asignar SEGUIMIENTO_ESTIMATE_PHP a una ruta inexistente y repetir
el test. Volver al PHP real después. Las mutaciones Python usan copias temporales,
jamás backend ni fixture canónica. Fuentes exactas no prueban despliegue actual
ni precisión/costo de respuestas reales.

## Renovación del paquete

1. Identificar checkout backend limpio y commit funcional autorizado. Revisar
   las cuatro fuentes y todos sus require; STOP si necesitan archivo extra,
   credenciales, datos o configuración. No copiar árbol entero ni secretos.
2. Exportar bytes de `git show COMMIT:ruta` para las cuatro rutas declaradas
   en FILES del verificador; no usar texto PowerShell que reencodifique/CRLF.
   Guardar esos blobs en las mismas rutas dentro del bundle y registrar
   source_commit/reviewed_head/contract2/SHA256 de cada archivo en manifest.
3. Comparar `--source` contra el checkout limpio: verifica HEAD, estado limitado
   a cuatro fuentes, bytes de source_commit y ausencia de drift de HEAD.
   La comparación usa blobsGit para evitar conversiones nativas de newlines.
4. Ejecutar negativos y cruce Dart/PHP0skip; revisar diff del bundle, hashes,
   paths allowlist y workflows antes de integrar. El cambio de contrato exige
   revisión del caller/parser; no actualizar un hash para ocultar divergencias.
5. CI remoto/Linux y publicación son gates separados del resultado local.
