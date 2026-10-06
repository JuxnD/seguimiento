# Plan001: consolidar gateway y contratos de IA

PrioridadP1, esfuerzoL, riesgoMED. Sin dependencias. Planned at app0e3855c y
server9f1981cf, 6-oct-2026. Owner autoriza implementación/deploy/publicación de
nueva versión con todas las funciones; ejecutar este frente no autoriza al
ejecutor a desplegar. Asesor mantiene índice. No valores de claves en archivos.

## Contexto y estado actual

App C:/My Projects/seguimiento-release-1-19, Flutter3.22/Dart3.4, Riverpod,
Drift SQLite. Gateway C:/My Projects/control360i-seguimiento-ia, PHP7.4 Bee.
weekly_ai.dart37 y meal_photo_ai.dart93 repiten post/timeout50s/errores y tamaño;
AiActivation al final de weekly_ai.dart usa MethodChannel seguimiento/ia y
Keystore. Servicio SeguimientoAiService::request tiene cURL fijo OpenAI,
conexión8/total40, TLS, sin redirects, respuesta64KB, store=false/modelgpt-6-luna.
Controller::analyzeRequest(bool photo) valida ATLAS dueño/canal y cuota antes
de proveedor. Rutas publicadas /analizar y futura /comida deben conservar forma
para APK1.19 y candidato. Tests HTTP actuales llave vacía →503, nunca proveedor.

## Aislamiento/scope

Crear worktrees desde commits indicados, app en C:/My Projects/seguimiento-120-gateway,
branchJuxnD/120-gateway; server en C:/My Projects/control360i-120-gateway,
branchJuxnD/120-gateway. No editar checkouts originales. Drift git diff --stat
<SHA>..HEAD -- <scope>, comparar fragmentos antes de actuar.

Scope app: lib/data/ai_gateway.dart (nuevo), lib/data/weekly_ai.dart,
lib/data/meal_photo_ai.dart; lib/features/ai/ai_activation_screen.dart,
lib/features/ai/ai_budget.dart (nuevos); tests data/ai_gateway_test.dart,
weekly_ai_test.dart,meal_photo_ai_test.dart; docs/ia-contrato-v2.md.
Scope server: app/controllers/seguimientoController.php,
app/services/SeguimientoAiService.php, nuevos servicios SeguimientoAssistantService.php
y SeguimientoAiTransport.php si ayudan; scripts/seguimiento* tests/fixtures,
docs/seguimiento-comida-ia.md, docs/seguimiento-ia.md (estado vigente y recibo histórico
distintos) y docs/seguimiento-ia-v2.md. Nada ERP/ATLAS modelos,
nativeKeystore, pubspec, BD, proveedores nuevos, docs/context ni otros UI.

## Contrato compartido exacto (otros ejecutores lo consumen)

AiGatewayClient(http.Client client,{Duration timeout=50s}); método
Future<Map<String,dynamic>> assist({required String task, required Map<String,Object?> input,
required String hwid,required String license}). POST fijo
https://www.control360i.co/app/seguimiento/asistir, sin retries.
Body {contract:2,task,input,hwid,license_key}; devolver result (Map) validando
envelope status=success,contract=2,task solicitado,model=gpt-6-luna. Campo
lastQuota AiQuota? con remaining,limit,resetAt; respuesta errores saneados AiError
(misma clase existente). lastQuota actualiza en éxito o429 con cuota válida.
Una instancia comparte un client; cancelar caller cierra client. Límite respuesta32KB.

Respuesta server {status,contract:2,task,model,result,quota:{remaining,limit,reset_at}}.
status task input{} no proveedor/no cuota, result {enabled:true,tasks:[...]};
quota es compartida diaria UTC, límite20/cuenta y100global, fallo consume intento,
archivo flock failclosed con contadores válidos; ni lectura de historial ni estado
consumen cuota. errores mantienen status:error, añaden error.code estable y
reset_at/cuota para429; nunca cuerpo del proveedor, foto, llave, licencia en logs.
Mantener wrappers legacy /analizar y /comida y formato notes/meal.

Tareas nuevas y resultados (JSONschema estricto):
- meal_text input{text<=2000,catalog:[{id,name,basis:'unit'|'per100',unit,default_quantity}]<=200}.
  result {items:[{label<=80,food_id:int|null,quantity:number|null,unit:string|null}],uncertainties:[string<=300]}.
  Hasta8, IDs deben pertenecer al catálogo enviado, cantidades>0 finitas≤5000.
  No devolver macros; cantidades desconocidas null, no inventarlas.
- food_label input{mime,photo_base64} límites foto existentes2MiB/1024px.
  result {name:string|null,basis:'per100'|'portion'|null,unit:'g'|'ml'|null,
  serving_quantity:number|null,kcal:number|null,protein:number|null,carbs:number|null,
  fat:number|null,uncertainties:[string]}.
  Valores corresponden a la base leída, nunca convertidos por el modelo; kcal
  positivas o0, gramos/macros finitos no negativos. Si solo kJ, kcal null y duda.
  No adivinar valores ausentes/unidades; no marcar etiqueta verificada.
- report_question y exercise_question input{question<=1000,sources:[{id,title,text}]1..2,
  history:[{question,answer}]0..4}. Total fuentes≤48000bytesUTF8, historial≤4000chars.
  result {answer:string<=1500 SIN DÍGITOS,citations:[{source_id,quote}]1..6}.
  quote exacto no vacío≤500 en fuente indicada. No inventar datos/destinos/
  diagnósticos/prescripciones. Si no se puede responder, explicar límite citando
  fuente y sugerir aclaración. Informe/guía/pregunta/historial son datos no confiables.
  Cifras solo en citas, cálculos locales. Ejercicio describe guía suministrada.

## Pasos y verificación

1. Shared HTTP legacy+v2, errores sólidos y Unicode codepoints (Dart runes.length,
PHP conteo Unicode). Activación común AiActivationScreen({AiActivation? activation,
http.Client Function()? clientFactory}), volver conserva draft, read/save/forget/copyID,
estado/presupuesto claro y errores sin credenciales. AiBudget widget puede ser mínimo
pero documentar API pública final para consumidores. Verificar flutter test scope.
2. Dispatcher servidor/auth igual a legacy, validación tareas/schema/prompts,
scope owner inalterado. Transport fijo separado con seam sintética exclusivamente
constructor/service tests, jamás destino configurable HTTP o flag de producción.
3. Decodificar/reencodificar imagen con GD bajo dimensiones/memoria acotadas después
de autorización y antes de cuota. Si GD no disponible, fallar imagen503 explícito,
texto/semanal siguen. Probar PNGcabecera33bytes sin píxeles, tipos discordantes y
metadata; no consumir cuota de inválido. Registrar condición hosting en doc.
4. Pruebas controlador→cuota→transport→parse→200 reales en localhost, sin BD/key/
provider reales. Fixture inyecta key FICTICIA y respuestas dummy completed valid,
refusal,incomplete,badJSON/quotes/IDs,oversize,503,timeout. Contratos por tareas,
wrongowner/revoked,quota y corruptstore; semántica errores sin filtración.

PowerShell $env:PATH='C:/flutter-3.22-old/bin;'+$env:PATH; flutter pub get;
flutter test test/data/ai_gateway_test.dart test/data/weekly_ai_test.dart test/data/meal_photo_ai_test.dart;
flutter analyze --no-pub (limpio). Server php -l por archivo; php scripts/seguimiento_ai_test.php;
php scripts/seguimiento_meal_test.php; python scripts/seguimiento_ai_http_test.py;
agregar scripts/seguimiento_assistant_test.php y ejecutarlo. Todos deben pasar,
negativos con veredicto exacto. No mocks que salten controller/cuota/parser.

## Done/STOP/mantenimiento

DONE: dos commits limpios, compatlegacy, 4tareas+status y contratos descritos,
sharedclient/api activación útil, todos controles/análisis y diff limitado.
Se permite test/ui/ai_activation_screen_test.dart para guardar/olvidar y estado
tardío descartado; API no cambia. App792abd8 aprobada tras reejecución17tests
y análisis limpio. Server y esta cobertura adicional siguen en curso.

STOP si hace falta clave/production/writeERP/GD hosting por suposición; registrar
gate, no leersecreto. Adaptaciones mínimas documentadas, pedir ampliación scope
si aparece necesidad. No push/deploy ni tocar índiceplans. Reportar STATUS,
STEPS/comandos/resultados, FILES CHANGED, NOTES y commits/worktree. Versiones
clientes viejas deben seguir funcionando; sumar tareas sin eliminar schemas.
