# Preparación012: privacidad, evidencia y piloto

9-oct-2026. Autoridad: owner autorizó implementar cinco planes con Claude;
coordinador asignó sólo los slices independientes de012 antes de008–011.
Worktree `C:/My Projects/seguimiento-012-piloto`, rama `JuxnD/012-piloto`, base
`d2d3070d6934eef2f70512e9cdea0b588b9c66a3`, candidata1.22.0+30/schema20.
Sin push, merge, release, servidor, teléfono, usuarios externos ni modelo real.

## Resultado implementado

- Ajustes declara inventario completo, historial IA y ZIP sin cifrar; requiere
  confirmación antes de crear/compartir. Cancelar no llega a host/plugins.
- Restauración declara reemplazo de IA, posible recuperación de conversación
  borrada y conservación de flags/cronómetro/licencia. Copias automáticas
  declaran IA y formato sin cifrar; no cambia su retención de cuatro.
- BorradoIA explica que sólo afecta base actual, sin purga de copias/externos
  ni servicio remoto. Confirmar/cancelar se verifican al releer SQLite.
- Dialogos desplazables; botón Cancelar accesible en360x800/texto1.6.
- Verifier/gate independientes comparan manifest y artefactos completos, releen
  recibo y exigen APK/hash/source y aapt/apksigner. Faltantes o mutantes rechazan;
  un fixture no autoriza publicación. [Contrato](../../runbooks/pilot-release-gate.md).
- Caso viable, especificación de alta nueva, medición y matriz nativa escritos.
  Caso/piloto de uso no validado: baseline y resultados NO_MEDIDOS.

## Fuente y referencias

Se reutiliza Settings/AlertDialog, repositorio IA y BackupArchive/DatabaseHost
como verdad de inventario. No se cambiaron contrato ZIP, queries de borrado,
datos/migraciones ni firma. Referencias: docs/actualizaciones, AutoBackup y puente
AiCredentialsBridge noBackupFilesDir. El verifier121 permanece intacto y acotado
a su propio artefacto; las herramientas012 son una frontera nueva.

## Pruebas y límites

| Prueba | Evidencia / resultado |
|---|---|
| Rojo antes de fuenteUI | [3 fallos funcionales](2026-10-09-012-evidence/disclosure-red.txt): inventario IA/cifrado, revisión previa y alcance de borrado. Fallo inicial de preparación por database.g.dart ausente fue corregido regenerando sobre schema20, no contado como rojo funcional |
| Lote acotado final | [55 tests Flutter pasan](2026-10-09-012-evidence/targeted-green.txt), concurrency1, timeout habitual: history_import, seed_plan, backup_archive, auto_backup, release121_flows, steps_base_settings, 5disclosureUI y wrappergate |
| Gate/negativos | [17 tests Python](2026-10-09-012-evidence/gate-green.txt): comparación positiva y SHA/firma/schema/datos/fases/recibo/herramientas ausentes. El wrapper Flutter vuelve a ejecutar esos17; no sumar como tests nativos adicionales |
| Análisis | [Sin problemas](2026-10-09-012-evidence/analyze.txt) con SDK3.22/Dart3.4 |
| Parser metadata contra APK real existente | [Rojo](2026-10-09-012-evidence/metadata-parser-red.txt) por formato V2 Signer no cubierto en mock; [verde](2026-10-09-012-evidence/metadata-parser-green.txt) tras admitir esa salida real. aapt/apksigner leen1.22+30/target34/firma histórica desde el APK previo en seguimiento-ilustraciones. No es APK del slice012 ni nueva instalación/upgrade |
| Diff | git diff --check=0; fuente ajena y schema preservados |
| Contexto estructural | [Validador exit1,18 incompatibilidades](2026-10-09-012-evidence/context-validator.txt): biblioteca española canónica no usa nombres/headers literales del validador. INDEX ya declara ese mapeo histórico. No afirmar verde de estructura ni duplicar docs para ocultarlo |

Un lote paralelo anterior falló por timeout en testlegacy de respaldo y espera
fija de confirmación del harness. La espera nueva observa la frontera real
(sin omitir assert) y el lote final secuencial pasó sin ampliar timeout. Ninguna
prueba demuestra continuidad nativa de un APK nuevo ni comprensión del owner.

Comandos finales desde raíz del worktree:

```powershell
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/dart.bat' run build_runner build --delete-conflicting-outputs
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test test/data/history_import_test.dart test/data/seed_plan_test.dart test/data/backup_archive_test.dart test/data/auto_backup_test.dart test/ui/release121_flows_test.dart test/ui/steps_base_settings_test.dart test/data/backup_disclosure_test.dart test/tool/pilot_release_gate_test.dart --concurrency=1 --reporter expanded
python tool/pilot_gate_test.py
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' analyze
git diff --check
```

## Estados de cierre y siguiente gate

**Implementación del slice independiente:** completa con diff revisado.
**Validación local:** host/UI sintéticos y tests gate ejecutados; nativo no
ejecutado. **Cierre formal012:** pendiente; preparación parcial, no piloto activo.

No realizados: alta/perfil/legado aislados; migración; política OSbackup;
SDKtarget36/spike/runtime; recibo nativo de candidato integrado; conexión del
gate al workflow y simulación que bloquee release; flujo nuevo008–011;
precisión comida/aceptación figuras; participantes/baseline/ventana/umbrales.
No se cifró ZIP ni purgó copias. No se llamó IA ni prestó credenciales.

Coordinador integra commits independientes tras revisar diff, resuelve contexto
con008–011 y fija candidato. Luego ejecutar alta/QA nativa con APK exacto y
cerrar caso/política antes de declarar PREPARADO_PARA_PILOTO o publicar.
