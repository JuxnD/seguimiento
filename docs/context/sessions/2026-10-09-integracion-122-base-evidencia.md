# Integración local122: baseClaude y evidencia008

Autoridad: integrar localmente en worktree aislado, sin publicar ni tocar rama
owner, teléfono, AVD o producción. Se verificaron ruta/rama inexistentes y
worktrees antes de crear:

- Checkout:`C:/My Projects/seguimiento-122-integracion`.
- Rama:`JuxnD/122-integracion`.
- Base exacta:`929f2897c73a86760cc73ce228a89f3aaa3789a8`.
- Candidata1.22.0+30/esquema20, sin migración ni cambioSDK/dependencias/firma.
-15a45a4→5d35bb2; f65bc84→bb1a707 por cherry-pick aislado.

## Conflictos y decisiones

No conflictos textuales en los dos cherry-picks. Se revisaron los automerges
de guía yTestMode. Se conservan calentamiento y sus relojes, checklist
PreAttemptCard, warmupDone/warmupSkipped, modo técnico y guion congelado/
reanudación, junto con todos los DTO/resolvers/guardas de fecha008.

La revisión encontró una interacción semántica previa del pipeline: la sesión
técnica nueva (`mode=tecnica`) podía mezclarse con fuerza normal para sugerir
subir carga. El coordinador autorizó corrección mínima en ESTA integración:
portar mode desde SQLite, filtrar lectura por protocolo y abstener subida en
técnica o modo incompatible. null corresponde a normal tal cual fuente;
no se inventa `strength` ni se deduce técnica de RIR4/RPE/nombre.

Las observaciones se conservan: no borrado/reclasificación histórica y la carga
registrada sigue visible. NormalRIR4 sigue siendo normal; si fue comparable
y cumple regla anterior puede conservar consejo. Reanudación/calentar no se
reinterpretan ni se reconstruyen por esta corrección.

## Evidencia

- Antes del ajuste de mode,41 controles del automerge pasaron.
- [Rojo contra bb1a707](122-mode-red.txt): tres fallos por assertions
  (se elegía técnica en vez de normal; guía técnica y guía normal desde técnica
  mostraban+2–5kg), con control positivo normal/normal que pasó.
- [Verde](122-mode-green.txt): cuatro casos con SQLite→política→pantalla;
  el historial permanece idéntico y la carga observada sigue visible.
-49 tests dirigidos de evidencia, fecha/reentrada, guía/snapshot, calentamiento,
  checklist, comboC01 y sesión técnica/reanudación pasan.
- Analyze sin hallazgos; suite integral659pasaron/16skips opcionales/0fallos;
  diff sin errores. Fuente fija durante los gates. Logs completos bajo
  `build/122-{focused,analyze,suite}.txt` del worktree.

Comandos de este worktree:

```powershell
$sdk122 = 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat'
& $sdk122 pub get
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/dart.bat' run build_runner build --delete-conflicting-outputs
& $sdk122 test --concurrency 2 test/domain/progress_evidence_test.dart test/data/progress_evidence_test.dart test/ui/progress_evidence_test.dart test/ui/release121_flows_test.dart test/ui/guided_session_test.dart test/domain/warmup_test.dart test/ui/guided_warmup_test.dart test/ui/pre_attempt_card_test.dart test/ui/suspicious_combo_test.dart test/ui/technique_resume_test.dart test/data/technique_session_data_test.dart --reporter expanded
& $sdk122 analyze
& $sdk122 test --concurrency 2 --reporter expanded
git diff --check
```

GeneraciónDrift existente necesaria en checkout limpio; archivos derivados y
logs bajo build/. No schema nuevo, no instalación nativa.

## Límites

Esta integración incluye únicamente baseClaude929 y008 más la interacción
de modo autorizada.010catálogo21,009metas22,012piloto y013logo se integran en
pasos posteriores con aprobación del coordinador; ningúnWIP ajeno se copió.
No equivale a APK publicado ni demuestra aceptación de figuras por el owner.
