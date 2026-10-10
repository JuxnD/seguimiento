# Plan025 · Estado de actualizaciones veraz

10-oct-2026. Implementación local completa; integración, APK/publicación y
aceptación física pendientes. Base `53524400994788d13ac94906fa5093d560c6f97a`,
worktree `C:/My Projects/seguimiento-025-version-visible`, rama
`JuxnD/025-version-visible`. No se tocó la integración ni otros worktrees.

## Problema y cambio

UpdateService conserva `release` sólo cuando su versión es más nueva. Por eso
`release == null` sin error no demuestra que el APK instalado esté publicado:
una instalación1.22 frente a pública1.21 también produce ese resultado.
UpdatesCard decía «Estás en la última versión publicada» y ahora dice
«No hay una actualización más nueva disponible». La versión instalada se
muestra por separado. Cambio de producto: exactamente una línea de texto.

Fuente/referencias: UpdatesCard, UpdateService, `domain/version.dart`,
`UpdateLauncher`, providers existentes, AppCard/tema y ADR0006. Se reutilizan
comparador, hasUpdate, timeout de10s,API y canal de descarga; no nuevo servicio,
modelo/versionamiento, navegación ni descarga automática. No se modifican
SettingsScreen012, esquema23, metas, SDK3.22/Dart3.4, dependencias/lock,
versión/pubspec, MainActivity, backend o datos.

El plan025 aporta la lectura independiente de Root sobre APK1.22/code30 en
AVDNailPro5554 y latest pública1.21. Esta sesión no inspecciona Android ni
GitHub vivo; esos hechos no se convierten en autoría/source del APK mostrado.
No se usaron AVD, teléfonos, usuarios reales, instalaciones/limpieza ni otro lanzamiento.

## Preparación y procedencia

No AGENTS.md/CLAUDE.md versionado en esta raíz ni AGENTS en C:/My Projects o C:/;
se conserva el contrato común suministrado por el owner. INDEX/actualizaciones/
ADR0006 y skills de contexto/dueño/anti-falso-verde guían el alcance.
`ctx_repo_brief→ctx_discover→ctx_change_scope`: procedencia estructurada5352440,
índice5352440, rama correcta,0archivos antes del trabajo; snippet recortado
contrastado con fuente completa. No reindexado ni autoridad inferida de grafo.

`flutter3.22 pub get --offline` terminó0; lock intacto. Generación Drift normal
`dart run build_runner build --delete-conflicting-outputs` terminó0 con425outputs
ignorados/1470acciones (4m41s de build); warnings de espera/resolución preservados
en salida del proceso, no atribuidos a fallo de producto. No generados a mano.
Las búsquedas iniciales de AGENTS/CLAUDE inexistentes y una raíz mal escapada
produjeron missing-file: preparación, NO rojo funcional ni bug de app.

## Rojo → verde y límites

Baseline existente:11tests pasan antes del cambio. Luego una nueva prueba
`test/ui/updates_card_test.dart` monta UpdateService real con MockClient, providers
reales (override versión/servicio) y UpdatesCard real. No hay red. Ante1.22
instalada/response pública1.21, assertion esperaba el mensaje factual y encontró
0 coincidencias; texto real registrado: «Actualizaciones | Versión instalada:
1.22.0 | Estás en la última versión publicada». Exit1 funcional, sin errores de
import/setup. Fuente previa y test se conservaron junto al log.

Tras cambiar sólo el texto,20/20 pasan,0skips/exit0:9UI y11regresiones de servicio,
canal y comparador. Incluye versiones iguales/posteriores sin actualización,
versión anterior con update,404 sin publicación/503 con motivo visible,
360dp texto1/2 sin overflow, sin llamada nativa automática y exactamente una
llamada `openApkDownload` con URL APK ficticia tras tocar. Las fuentes Roboto y
MaterialIcons versionadas son del harness; tema/layout de producto sin cambio.
Los tests de launcher existentes conservan fallbacks; no se prueba instalador
Android real ni descarga HTTP. No se convirtió un mock en aceptación física.

Análisis final `flutter analyze --no-pub`:exit0/No issues found. Diff-check0.
El validador genérico de biblioteca terminó1 con17 requisitos de shape inglés
(# Project context/Read this first/Context map/Freshness y PRODUCT/REFERENCES/
DOMAIN/ARCHITECTURE/OPERATIONS/DELIVERY/EVIDENCE). Ya están ausentes en5352440:
la biblioteca canónica usa nombres en español y un mapa explícito de equivalentes
en INDEX. Este límite de herramienta no es un análisis Dart ni una prueba UX;
no se afirma validación genérica verde ni se rehace la biblioteca fuera del025.

No fullsuite por una línea de copia: la full de candidata integrada corresponde
al coordinador; no se presta la de otro commit. Sin push/publicación/AVD.

Comandos desde esta raíz, SDK fijo:

```powershell
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --reporter expanded test/data/update_service_test.dart test/data/update_launcher_test.dart test/domain/version_test.dart
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --reporter expanded test/ui/updates_card_test.dart --plain-name '1.22 instalada sobre pública1.21 no acredita publicación'
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --reporter expanded test/ui/updates_card_test.dart test/data/update_service_test.dart test/data/update_launcher_test.dart test/domain/version_test.dart
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' analyze --no-pub
git diff --check
```

El segundo comando se ejecutó sobre fuente vieja y falló como corresponde;
sobre fuente final debe pasar. Evidencia raw portable y manifest de hashes:
[025-evidence.zip](025-evidence.zip). Cada log incluye comando/exit/stdout/stderr;
los snapshots se guardan comprimidos, sin copia parcial de Dart bajo build.

## Cierre

Implementación completa y comportamiento local renderizado verificado. Operación
Android/publicación/aceptación humana no verificadas aquí. Root revisa la fuente y
el integrador008 toma el commit aprobado. Gate023/024 permanece independiente.

Cápsula SHA256 `92767f9e278daa02c9d08d04716e7b06ee8007563aa793c78f2a20750fa603d2`, 23314 bytes; 13 entradas idénticas a los archivos/logs capturados. El manifest separa raw bytes y forma LF canónica para cotejar blobs Git sin fingir igualdad de CRLF.
