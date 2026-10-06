# Plan003: historial local, preguntas con fuentes y accesos útiles

P1/L/MED, depende001DONE; paralelo002 con archivos disjuntos.
Planned at app0e3855c,6-oct-2026. Usuario autoriza todasfunciones yrelease.

## Contexto/fragmentos actuales

App Flutter3.22/Dart3.4 Riverpod Drift, local-first. ReportScreen153 pasa solo
WeeklyAiScreen(report:report.value!). WeeklyAiScreen23 _notes enState,102
lo borra al enviar;241… muestra notas con copiar/share. AiNote(kind,text,quote)
exige cita literal y narrative sin dígitos. Providers315–327 reportInput observa
sesiones/comidas/peso…pero no sueño/date; ReportRepository133 carga sueño y180
today:today??DateTime.now(). load171–174 carga períodoanteriorigual longitud.
TechniqueContent84–158 ya combina ExerciseDetail.forLoad(loadKg,grip), notas
personales, variantes, progresión y anclaje. No enviar fotospropiasnihistorial
entrenamientodesde guía. Esquema17. Migrationtest86 crea esquemaACTUAL y88
asume version>=17 actual, no es fixture17independiente. BackupexportSQLite y
DatabaseHost225 valida quickcheck/todas tablas/FK y trialopen/migra.

## Scope/aislamiento

Worktree C:/My Projects/seguimiento-120-informes branchJuxnD/120-informes desde
app001aprobado. Scope lib/data/tables.dart,database.dart,database.g.dart,
lib/data/repositories/ai_conversation_repository.dart(nuevo),report_repository.dart,
sleep_repository.dart; lib/app/providers.dart;
lib/features/report/weekly_ai_screen.dart,report_screen.dart;
lib/features/ai/ai_conversation_screen.dart,ai_history_screen.dart(nuevos),
lib/features/training/technique_sheet.dart;
lib/domain/ai_context.dart y ai_actions.dart(nuevos); se aceptan helpers equivalentes
lib/domain/ai_report_sources.dart y lib/domain/report/missing_data_actions.dart
para mantener las fuentes/acciones cerca de su dominio; tests data migration/history/
providers/backups, UIhistory/question/actions/guide; integration_test/ai_history_test.dart;
test/fixtures/schema17-synthetic.sql o .sqlite; docs/ia-informes.md,
docs/modelo-datos.md (migración18). DatabaseHost solo si necesita extensión
de validación condicional (legacy17 válido); backup_archive sin nuevo formato.
No comidas/foods/native/pubspeclib ni backend. No índiceplans.
Extensión acotada de revisión: `lib/data/ai_gateway.dart`,
`lib/features/ai/ai_activation_screen.dart` y `ai_budget.dart`, junto a sus
tests, para reutilizar `status` gratuito y su presentación en Weekly, preguntas
y activación. El contrato `assist`, transporte y rutas permanecen iguales.

## Shared contrato001

AiGatewayClient(client).assist(task:'report_question'|'exercise_question',
input:{question,sources:[{id,title,text}]1..2,totalUTF8≤48000,
history:[{question,answer}]≤4,total≤4000},hwid,license) devuelve
{answer≤1500 SIN DÍGITOS,citations:[{source_id,quote exacto≤500}]1..6}.
Resolver cadaquote contra fuente correcta; rejectunknownIDs/quote no encontrado,
duplicatecitations sane; guardrailsdescriptivos/noautoprescripción, no URLs/
operacionesgeneradasporIA. GPT6Luna storefalse. source snapshotsinmutables,
userescogecontexto yconsiente cada pregunta. AiActivationScreen común conserva
contexto y read segura; budget lastQuota/status visiblenomodelcall.

## Pasos

1. Snapshot exacto con id/title/text, período/timestamp/model/contract/hash.
SQLite18 tablas AiConversations y AiMessages o análisisturns equivalentes,FK;
repo createread/list/delete clear, límitesdehistorial visibles no crecimiento
silencioso (p.ej.100conversaciones,20turnos; advertir/permitir borrar), jamás
licencia/HWID/photo/clave almacenada. Guardar solo éxito validado. Semanal
guardarautomáticamentesilocalconfigurado; producciónReportScreenpasarepo.
Reabrir/borrar desdeInforme; fuenteoriginal permanece si usuario corrige registros.
Indicar 'Análisis guardado' conrango/fecha,no reemplazar porinformeactual.
2. Congelar fixture sintética17deDDL anterior, no construirnuevoesquema y
renombrarversión. Migrar18 y tests17→18 con comidas/fuentespreservadas, ZIPA→B
lleva conversacionessnapshots, legacy17sinAIrestaura/migra; rollbackfallo protege
baseactual. Actualizarhelpermigra existentes para nofalsegreen17. build_runner
PATH3.22. Ningunamigraciónsistemaactualencheckoutsusuario.
3. Corregir invalidación sueñorangosactual+previo y notas/fecha siafectan
informe; observarstreamsreales y pasartodayProvider a load. Test primercargar→
set/remove sueño→releer sinotromodulo. No refactorgrande todosproviders.
4. Preguntas desdeanalisis/historial: textbox y contextoexactopreview,
compararperíodoanterior opciónexplícita usando funciones de dominio actuales,
cifraslocales encontexto precomputado/snapshot (no calculadas porLuna).
Historiallocal dechat, citas consource_id/title visible,copy/share concontexto,
cancel/dispose/timeout/429/invalid quote sinpersistirlate. Reanalizaractual
crea otro snapshot,histórico noreescrito. Consent resetcuando cambiaquestion/context.
5. Accesosdatosfaltantes deterministasfecha/rango,tipo destinoenum local,
no parsearliteralmodelquotecomoURL/date. Generar desdeReportInput/datos
dominio: faltanpeso→pesajefechaelegida (si0enrango ofrecerdía),comidasincompleta
→MealFormScreen/Comidasdía concreto, pasos→formularioexistente. Abreform,
noescribe. Conhistorialantiguo datosyaresueltos mostrar resuelto/recalcularactual,
conservarcomentariooriginal; noautocrearregistro. Testsfechahistórica/noactivación.
6. Explicar ejercicio botón enTechniqueContent/hoja conguía seleccionada,
carga/agarre/notaspersonales/progresión/anclaje exactos visibles. Construir
fuente reutilizando forLoad nosegundacopiaguía. Pregunta al mismoConversationScreen,
citaverificada ylink 'Ver guía' vuelve alpaso/figura correspondiente; nunca
evalualesiones ni cambia plan. Fuentecreada sinfotos; no mandarregistrocorporal.
Activación/budget común, fonts/Wraptexto1.6 consistentes.

## Tests/comandos

$env:PATH='C:/flutter-3.22-old/bin;'+$env:PATH;
flutter pub get; dart run build_runner build --delete-conflicting-outputs;
flutter test test/data/migration_test.dart test/data/restore_test.dart
test/data/backup_archive_test.dart más nuevos ai_history/provider/UI;
flutter analyze --no-pub → limpio. PatronesSQLite test/data/repositories_test.dart,
test/data/backup_settings_test.dart, fuentes test/support/test_fonts.dart.
Sourcenumericaloracle fijo: snapshots ficticios conpeso70 y72, citaractual
consourceprevio yanlışIDdeberechazar; respuesta inventada/noquotes nopersistida.
Nativeposteriorroot pruebareinicio/ZIPsource ycaminoformulario, sin proveedorreal.

DONE: historialpersistente(+backups/migration frozen),reportfresh,QA/compare,
actionfechaslocales y guía desdecontextoreal,todos tests/análisis/diffscope ydocs.
STOP sisharedcontrato001 noexiste, sourcecitaseguíamismatch, backupsregresan,
se requeriría secretodatos reales, archivos fueraScope o fallo2veces inexplicado.
No push/deploy, noeditplansREADME. Commitenworktree yreportSTATUS/STEPS/FILES/
NOTEScomandos+commit. Notes sobre límites reales, no afirmaraceptacióndeowner.
