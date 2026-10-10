# 0020 — Alta neutral y arranque protegido (plan 022)

Fecha: 2026-10-10. Estado: implementada en candidato local
`JuxnD/022-alta-neutral-claude` (base `f34ab7c`), **sin integrar ni publicar**.
Descompone el frente 012; esquema **23** reservado aquí. No cierra el producto
ni el piloto: falta el cierre 012 de lectores (ver «Pendiente obligatorio»).

## Contexto

En f34 una instalación nueva heredaba al dueño: `onCreate` aceptaba cinco
metas, `main.dart` sembraba en cada arranque con plan vacío el plan v1/v2 y la
fecha 2026-08-26 (`seedIfEmpty`), y `applyPendingCorrections` sin ningún permiso
creaba 20 sesiones, 197 series, 8 partidos, 9 medidas, 3 pesos y pasos del
traspaso. El shell (permisos, pasos, respaldo, avisos) se montaba siempre.
[Rojo funcional archivado](../context/sessions/evidence/2026-10-10-022-red-f34.txt).

## Decisión

- **Estado en SQLite** (`profiles`): origen `new|legacyUnknown`, estado
  `pending|ready`, `setup_confirmed_at`, `handoff_consent_at`. Nada en
  `flags.json`. `onCreate` = new/pending sin metas; migración = legacyUnknown/ready.
  Inválido → `InvalidSetupException`, visible, no se corrige.
- **AppEntry** (`features/onboarding/app_entry.dart`) es el `home` de la app:
  pendiente → alta/restaurar; listo → `HomeShell` (sus efectos corren al
  montarse, una vez); error → pantalla con restaurar. Reconsulta con la
  generación de la base. Listo→pendiente con la app abierta retira avisos;
  `rescheduleRemindersProvider` además se niega sin alta lista.
- **Arranque**: sólo `seedFoodsIfEmpty` (catálogo y combos compartidos) y
  ajustes de avisos. `seedIfEmpty` queda como fixture del dueño en pruebas; ya
  no corre en producción. Sin plan, Hoy muestra «Sin rutina configurada» y abre
  el editor común (`PlanEditScreen` con `PlanDraft.empty`); no hay plantillas
  ni segundo motor. La sugerencia de activar el v3.1 se oculta sin plan y para
  instalaciones nuevas.
- **Alta** (`ProfileRepository.confirmSetup`, una transacción): valida pendiente
  y sin registros personales ni metas, escribe perfil (fecha elegida, estatura/
  nacimiento opcionales, pasos 5.000 editables), acepta seis métricas con
  vigencia = confirmación real y marca listo. Doble confirmación → `false`.
  «Más adelante» = null conocido en las cinco nutricionales; el perfil conserva
  su proyección interna (130/160/2400/2000) que no se muestra como elección.
- **`GoalMetric.kcalFloor`** en el mismo core. Ajustes: una meta con vigencia
  null se muestra vacía «(sin meta)»; escribir una cifra la acepta aunque iguale
  la proyección (`updateProfile` acepta sobre null sólo campos presentes);
  editar la estatura no acepta metas. Política 009 intacta para valores conocidos.
- **Correcciones del traspaso**: `DataCorrection.apply` exige
  `handoff_consent_at`; `applyPendingCorrections(db, list, backup)` exige
  respaldo previo existente y revalida el consentimiento dentro de la
  transacción. Ni origen, ni flags «descartado» autorizan. El aviso de Hoy no se
  ofrece a instalaciones nuevas; el dueño conserva Ajustes › Correcciones con
  vista previa y autorización fechada.
- **Restauración común** (`features/settings/restore_access.dart`): Ajustes y
  el alta comparten selector/confirmación/progreso; parser, journal y reversión
  siguen en `BackupArchive`/`DatabaseHost`. `checkComplete` llama
  `validateSetup` en la apertura de prueba → un ZIP23 inválido o pendiente con
  registros se rechaza con 0 cambios de base, fotos y flags. ZIP/SQLite 20–22
  migran a legacyUnknown/ready. La licencia no entra al ZIP ni se hereda.

## API para 012/011 (contrato concreto)

```dart
// lib/data/repositories/profile_repository.dart
abstract final class ProfileOrigin { newInstall='new'; legacyUnknown='legacyUnknown'; }
abstract final class SetupState { pending; ready; }
class SetupStatus { String origin; String state; DateTime? confirmedAt; DateTime? handoffConsentAt;
  bool pending, ready, isNewInstall; static SetupStatus parse(ProfileRow) /* throws InvalidSetupException */ }
class SetupDraft { DateTime startDate; double? heightCm; DateTime? birthDate; int stepsTarget = 5000;
  int? proteinMin, proteinPreferred /* = proteinaMax */, kcalWeekly, kcalFootball, kcalFloor;
  void clearNutrition(); String? problem(DateTime today); }
Future<bool> ProfileRepository.confirmSetup(SetupDraft, {DateTime? now});
Stream<SetupStatus> ProfileRepository.watchSetup(); Future<SetupStatus> setupStatus();
Future<void> ProfileRepository.recordHandoffConsent({DateTime? now});
Future<SetupStatus> validateSetup(AppDatabase);  // contrato común app abierta / respaldo
const sharedReferenceTables; Future<List<String>> personalTablesWithRows(AppDatabase);
// lib/app/providers.dart (única adición de provider)
final setupStatusProvider = StreamProvider<SetupStatus>(...);
// lib/domain/goal_history.dart
GoalMetric.kcalFloor  // unit kcal, misma GoalHistory; GoalAt(known, value) ya distingue
```

Semántica que deben consumir los lectores (con los adapters 011 congelados):
`history.on(m, day)` → `null` = desconocido (antes de toda vigencia);
`GoalAt(known: false)` = legado no registrado; `GoalAt(known: true, value: null)`
= decisión «sin meta»; `kcalFutbol` null conocido hereda `kcal` conocida y, si
ésta es null, no hay objetivo. 022 **no** añade `goalHistoryProvider`, no cambia
`goalOn` global ni toca ReportInput/Stats/Builder/GoalSpan/gráficas/radar.

## Colisiones potenciales con 011 (no editadas aquí)

- `providers.dart`: 022 añade `setupStatusProvider` y una guarda al inicio de
  `rescheduleRemindersProvider`; 011 añade `goalHistoryProvider`/
  `personalRadarProvider`/dependencia de `reportInputProvider`. Distintas
  zonas; integrar a mano si el merge marca contexto.
- `goal_history.dart`: 022 sólo añade el valor de enum `kcalFloor` tras
  `kcalFutbol`. Si 011 itera `GoalMetric.values` o tiene `switch` exhaustivo,
  debe contemplar `kcalFloor` (en f34 no hay switch exhaustivo).
- `goal_repository.dart`: `goalsOfProfile` incluye `kcalFloor`; `seedGoalVersions`
  por métrica; `updateProfile` acepta sobre null. `historicalChartGoal` de 011
  sólo admite `'proteinMin'|'steps'`: no afectado.
- `ReportInput.referenceOn`/`kcalReferenceOn` (011) son los adapters que el
  cierre 012 usará; 022 no los duplica.

## Pendiente obligatorio (cierre 012)

Hoy, comidas, Ajustes (salvo la entrada «sin meta»), avisos, informe, ratios e
IA todavía leen el perfil proyectado: un usuario con «Más adelante» vería 130 g
o 2.400 kcal como meta. Ese cierre debe leer la historia vía adapters 011 sin
convertir null en 0 ni reintroducir placeholders. Hasta entonces **no activar
un usuario nuevo en la app diaria, ni publicar ni pilotar**. Tampoco:
`PlanScreen` sigue ofreciendo «Activar v3.1» a quien ya creó un plan propio
(fuera de los archivos autorizados); iOS `DarwinInitializationSettings` pediría
permiso en `init()` antes del alta (app Android; nativo no evaluado).

## Consecuencias

- Nuevos efectos iniciales deben vivir en `HomeShell` (detrás de AppEntry).
- Nuevas metas usan la misma `GoalHistory`; restaurar conserva origen/estado.
- Pruebas que modelan a quien ya usa la app usan `test/support/ready_profile.dart`
  (`asExistingUser`), equivalente a la migración; las de alta, una base nueva.
