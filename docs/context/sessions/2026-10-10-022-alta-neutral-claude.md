# Recibo 022 — alta neutral y arranque protegido (ejecutor Claude)

Fecha 10 oct 2026. Worktree aislado `C:/My Projects/seguimiento-claude-022`,
rama `JuxnD/022-alta-neutral-claude`, **source SHA base**
`f34ab7c9fd4107ffc728e2b9bfdd2153e00315a4`. Flutter 3.22.0/Dart 3.4 en
`C:/seguimiento-sdk-3.22.0`; sin cambio de SDK, lock ni dependencias. Drift
generado con `dart run build_runner build --delete-conflicting-outputs`
(`.g.dart` ignorado). Commit local único; sin push, merge, APK, AVD, teléfono,
servidor, licencias ni datos reales. Personas y datos 100 % ficticios.

Estado: **implementación local completa del alcance 022; no validado
operativamente ni cerrado**. El cierre 012 de lectores sigue obligatorio antes
de activar un usuario nuevo o publicar. Decisión y API:
[ADR 0020](../../adr/0020-alta-neutral-y-arranque-protegido.md).

## Rojo funcional contra base (antes de tocar producción)

`test/data/pilot_profile_test.dart` con sólo APIs de f34 →
[salida archivada](evidence/2026-10-10-022-red-f34.txt)
(SHA256 `85a41fc201efd3cbed389112d07930c85b2d60b2462de87ac79b807330afbf96`):
instalación nueva con 5 metas `inicio` aceptadas; `applyPendingCorrections`
sin permiso creó 20 sesiones/197 series/8 partidos/9 medidas/3 pesos/1 pasos
y 2 vigencias. No fueron fallos de import ni generación.

## Gates y pruebas nuevas

- `test/data/pilot_profile_test.dart` (27): new/pending sin nada personal;
  confirmar (6 vigencias desde la confirmación, fecha histórica no retroactiva);
  doble confirmación concurrente; fallo SQLite (trigger) revierte todo;
  validación sin escrituras; cancelar/reabrir deja pending; «Más adelante»
  null conocido; número igual al ejemplo aceptado; pending con registros no
  confirma; estatura no acepta; null→130 acepta (y no duplica); fútbol hereda,
  semanal null no inventa; piso opcional y editable; origen/estado/fecha
  inválidos visibles; correcciones sin consentimiento / con flags descartado /
  nuevo / legado / sin respaldo / consentimiento retirado = 0 escrituras;
  dueño con consentimiento + respaldo aplica; dos personas ficticias aisladas;
  ZIP23 ready y pending conservan origen/estado/nulos; ZIP inválido o
  inconsistente rechazado con bytes de base, fotos y flags idénticos; fallo
  tardío revierte alta previa y fotos; SQLite 22 → legacyUnknown/ready.
- `test/ui/pilot_onboarding_test.dart` (10): spies de permiso/avisos/pasos/
  respaldo en 0 mientras pending (también tras 3 min) y ejecutados al pasar a
  ready; Hoy «Sin rutina configurada», sin descanso, sin v3.1 ni correcciones;
  cancelar/empezar de nuevo; listo→pendiente con app abierta retira avisos y
  mata el temporizador; origen inválido → pantalla de error sin shell; alta a
  360 dp con texto ×1/×1.6/×2 (con y sin nutrición) sin excepción y con
  `TextScaler.linear(scale)` sin clamp. Capturas reales en
  `build/022-capturas/` (ignorado); versionadas las ×2:
  [alta-2.0](evidence/alta-2.0.png) `ccb4b908…18f5`,
  [alta-2.0-nutricion](evidence/alta-2.0-nutricion.png) `83783a38…e99`.
  La primera captura mostró etiqueta flotante truncada («Pasos diarios entre
  sem…»): se acortaron etiquetas y el detalle pasó a texto que se ajusta.
- `test/data/migration_test.dart`: 20/21/22 → 23 conservan cada tabla,
  columna y fila (por rowid), sin propuestas nuevas; desde 22 sólo
  `kcalFloor` legado+migración; 20/21 seis métricas. Resto de pruebas al 23.
- `test/data/schema21_122_integration_test.dart` (fixture real 21 congelada):
  esperado 23, columnas de alta y 12 vigencias (piso = `kcal_floor` físico).

Mutantes (revertidos): M1 sin `validateSetup` en `checkComplete` → ZIP inválido
aceptado, gate falla; M3 sin guarda en `rescheduleRemindersProvider` → 17 avisos
para un alta pendiente, gate falla.

Pruebas existentes adaptadas sin debilitar oráculos: las que modelan a quien
ya usa la app parten de `asExistingUser` (`test/support/ready_profile.dart`,
igual que la migración) y las de correcciones registran consentimiento y pasan
el respaldo; `goal_history_test` reemplaza «instalación nueva conocida desde
hoy» por «sin metas hasta el alta; 5.000 desde la confirmación».

## Comandos y resultados (PowerShell/Bash, worktree ejecutor)

```text
flutter test test/data/pilot_profile_test.dart           27/27
flutter test test/data/migration_test.dart               19/19
flutter test test/ui/pilot_onboarding_test.dart          10/10
flutter test <13 archivos afectados>                     91/91
flutter analyze                                          No issues found
flutter test (suite completa, una vez tras dirigidos)    +869 ~17 -0 (exit 0)
git diff --check                                         limpio (ver commit)
```

Antes del verde, una corrida completa de diagnóstico (819/17/40) mapeó las 40
pruebas que dependían de `onCreate` sembrando metas o de bases pendientes con
datos; se corrigieron fixtures, no producción. Tras la suite final sólo se
quitó un import sin uso de una prueba y se escribieron docs.

## Residuos y límites

- **Cierre 012 obligatorio**: lectores de Hoy/comidas/avisos/informe/ratios/IA
  siguen leyendo la proyección del perfil (un «sin meta» se vería 130/2400).
  Usar adapters 011 congelados (`ReportInput.referenceOn`, `kcalReferenceOn`,
  `historicalChartGoal`); sin null→0 ni placeholders.
- `PlanScreen` ofrece activar v3.1 (plan y metas del dueño) a quien ya creó un
  plan propio: fuera de archivos autorizados → 012.
- iOS pediría permiso de notificaciones en `init()` antes del alta; app Android.
- Esquema 22 y 20 de las pruebas se derivan del actual quitando columnas; sólo
  21 (y 17/18/19) son fixtures reales congeladas.
- Nativo, APK, upgrade sobre 1.21/1.22, AVD y teléfono: NO_EVALUADO.
- Colisiones potenciales con 011 detalladas en ADR 0020 (providers.dart,
  enum `kcalFloor`, `goalsOfProfile`/`seedGoalVersions`); no se leyó ni editó WIP 011.
