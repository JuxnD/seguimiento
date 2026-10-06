# Plan002: registrar comidas por foto/frase y preparar etiquetas revisadas

P1/L/MED, depende001 DONE. Planned at app0e3855c, 6-oct-2026; refrescar excerpts
solo si001 tocó sharedclient. Usuario seleccionó todo, no repetir aprobación.

## Contexto actual, core y convención

C:/My Projects/seguimiento-release-1-19, Flutter3.22/Dart3.4 Riverpod Drift.
MealFormScreen _editItem97 llama _rememberFree;222 persiste catálogo antes
de Guardar;190 asigna fromFood si coincide con etiqueta, promoviendo certeza.
MealPhotoScreen159–164 agrega porciones originales a notas sin distinguirlas
de edición posterior. PhotoFoodEstimate.toDraft devuelve foodId/sourceVerified null.
NutritionRepository.fromFood21–29 calcula localmente snapshot desde FoodRow.
FoodDialog en foods_screen.dart tiene base unit/per100, macros, fuente y guardar.
No duplicar core/persistencia/calculadora ni tocar esquema aquí.

## Scope y aislamiento

Worktree C:/My Projects/seguimiento-120-comidas branchJuxnD/120-comidas desde
app aprobado de001. Scope lib/features/meals/{meal_form_screen,meal_photo_screen,
foods_screen}.dart; nuevos meal_text_screen.dart,food_label_screen.dart;
lib/data/meal_assistant.dart (nueva DTO/client adaptación); meal_photo_ai.dart
(solo metadata/local compatibility después001), nutrition_repository.dart
(staging estrictamente necesario). Tests meal/photo/text/label/regression/UI,
integration_test/ai_meals_test.dart; docs/ia-comidas.md. Sin tablas/providers/
historial/report/guía/backend/native ni pubspec. No modificar índiceplans.

## Contrato001 a usar

AiGatewayClient(client).assist(task:'meal_text'|'food_label',input:Map,
hwid:...,license:...) devuelve resultvalidado, lastQuota. AiActivationScreen
activation/clientFactory opcionales para tests, reutilizar read/save segura.
MealText input{text,catalog:[id,name,basis unit/per100,unit,default_quantity]≤200}.
outputitems[{label,food_id int|null,quantity num|null,unit str|null}],uncertainties.
Label result{name nullable,basis per100/portion nullable,unit g/ml nullable,
serving_quantity nullable,kcal/protein/carbs/fat num|null,uncertainties}.
Imagen same prepareMealPhoto reencodifica sinEXIF≤2MiB/1024, vista previa y
consentimiento de esa foto; no guardar imagen. TodoPOST sin retry50s,
cancel/dispose descartanlate. No secretos ni comida guardada por red.

## Pasos

1. Corregir _editItem de ítem libre: edición solo en memoria, conservar
sourceVerified null y foodId null; no invocar _rememberFree para IA/foto.
Conservar alta manual explícita _addFree según contrato existente. Etiquetar
notas de foto como 'Propuesta original' y aclarar que el detalle final es el
registro corregido; no reescribir notas personales. Probar corregir→salir,
nombre/macros idénticos a FoodRow etiqueta, fusióncancelada, cambiar×/quitar
alimento e informe con propuesta claramenteoriginal. Relectura realSQLite.
2. Nueva entrada visible 'Describir comida · IA', campo frase con dictado
del teclado disponible. Enviar solo frase+catálogo reducido explicado en preview.
Resolver IDs localmente contra catálogo enviado. Macros siempre calculados
con macrosFor/fromFood. Cantidad null muestra 'Falta cantidad'; usuario
acepta porción habitual explícitamente o introducecantidad. IDnull/ambigüedad
requiere elegir alimento local, nunca elegir por igualdad de nombre ni inventar
macros. Quitar opcional, selección y cantidades validadas; no añadir irresuelto.
Añadir devuelve mismo borrador; Guardar actual registra. Preservar fecha/franja/
hora/notas y existentes; vacío/offline/cancel/429/invalid output claros.
3. Entrada 'Leer etiqueta · IA' en catálogo (y selectorNuevoAlimento si encaja
sin rehacer formulario). Mostrar foto y campos leídos; base/porción/unidad y
incertidumbres. Valores son de baseleída. Si porción30g, normalización opcional
local ×100/30 explicada; si100ml, baseper100/unitml. Si faltan unidad/base/macros,
pedir completar sin cero inventado; kJ no se toma como kcal. Precargar FoodDialog
con un borrador tipado/initial values, no FoodRow persistido ni save antesrevisión.
Fuente etiqueta solo tras checkbox explícito 'Comprobé valores y porción con
el empaque'; antes sourceestimado/revisión, no autoverificada. Cancel no catálogo.
Guardar FoodDialog core, validar antes de convertir. No perder semillafuentes.
4. Activación directa desdefoto/frase/etiqueta conservando draft, budget/reset
visible (leer taskstatus no consumoAI), consentimiento separadoporimagen/frase.
Usar tema negro/naranja y widgets/chips existentes, Wrap y accesibilidadtexto1.6.

## Verificación y tests

Flutter PATH C:/flutter-3.22-old/bin. flutter pub get;
flutter test <todos nuevos tests y test/data/meal_photo_ai_test.dart,
test/ui/meal_photo_screen_test.dart>; flutter analyze --no-pub limpio.
Seguir test/ui/meal_photo_screen_test.dart y integración ai_actions_test.dart:
MockClient solo red, cálculo/Navigator/SQLite reales. Casos frase2huevos:
catálogo ficticio1huevo70kcal/6P →140kcal/12P, ninguna fila antesGuardar,
IDinventado/qtynegativa/ambigua no se agrega. Etiqueta porción30g150kcal/P3→
per100500kcal/P10 (local),100ml,missingunit,kJ,checkboxfalse→noEtiqueta,
cancel→nofoods. Error404/429,timeout,cancel Late,Unicode.
Capturas opcionales test/fixtures fontsRoboto (text/chip/button/AppBar),360×800
texto1.0/1.6, sin overflow y sinAhem; artefactos en ignored/tmp.

DONE: todasfuncionesenrutasvisibles y ningunaescritura prematura/falsa certeza,
testnegativos+oráculos/relecturas, análisislimpio, docs y diff enscope, commitslimpios.
STOP sicontrato001 ausente/mismatch, dependeesquema fueraScope, pideproviderkey
o datosreales, verificación falla2veces sincausa. Sin push/deploy/publicación
ni activarlicencias. ReportarSTATUS/STEPS/resultados/FILES/NOTES+commit.
