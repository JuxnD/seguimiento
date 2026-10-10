# Dos harness de comidas: desplazamiento y toque real

WT aislada `C:/My Projects/seguimiento-024-ci-probe`, base `cdcc9df`, producción
idéntica a604release. Sólo `meal_form_free_edit_test.dart` y
`meal_form_free_replace_test.dart`; no fixtures, producto, viewport, tema,
SDK, dependencias, tiempos, backend ni dispositivos modificados.

RawCI37e entregado por008 y leído: Yogur recibió un tap en Offset368,611.9 fuera
del render800×600; Entrada libre no recibió el tap y después no había campos
del diálogo (IndexError). Fuente remota original preservada por008 en
release123-ci-evidence; hash del raw vinculado al manifiesto de este tramo.

Una baseline local de los mismos dos archivos dio0pasados/2fallos, exit1,
reproduciendo los toques fallidos y la ausencia del diálogo. Luego sólo se
añadió ensureVisible, pump/settle existente y assertion hitTestable antes de
tocar Yogur/Entrada libre. Se reforzó igual la visibilidad del Guardar final,
que ya tenía ensureVisible. No se sustituyó la interacción por llamada directa
ni se relajó ninguna comprobación de datos o del catálogo.

Una sola corrida posterior dio **2/2**, exit0,7s del reporter/13,86s del proceso.
Watchdog externo120s no activado. Se conservan verificaciones originales:
editar no enlaza/verifica catálogo antes de Guardar, alimento original intacto,
mealItem libre persistido; homónimo por100g no ofrece Actualizar, copia porción
y combo original sin cambio. No fue necesario cambiar ningún helperSQL.
Análisis0 y diff-check0; sólo12líneas añadidas/2sustituidas en esos dos tests.

```powershell
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --reporter expanded test/ui/meal_form_free_edit_test.dart test/ui/meal_form_free_replace_test.dart
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' analyze --no-pub
git diff --check
```

Logs crudos comprimidos, resultados, comandos y hashes de los dos source
probados/analizados en [manifiesto](meal-scroll-evidence/manifest.json).
No otra suite completa, mutante o captura. Linux final lo ejecuta CI de008;
este resultado no acredita el teléfono ni publicación.
