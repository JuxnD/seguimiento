# Plan004: integrar y publicar la versión completa autorizada

P1/L/MED, depende001/002/003 aprobados. Fuente inicial app0e3855c y server9f1981cf.
No ejecutar hasta cerrar sus criterios. Owner autorizó toda la nueva versión,
despliegue de rutas IA y publicación después de Improve el6oct. No repetir permiso.

## Autoridades

Original app C:/My Projects/seguimiento, branchv34/manana-y-dia-completo@c5b84e7
dirty no tocar. Candidato C:/My Projects/seguimiento-release-1-19 branch
JuxnD/ia-comidas-foto@0e3855c, solo planes de este audit pendientes. Integration
debe ser un nuevo worktree C:/My Projects/seguimiento-120-release y branch
JuxnD/120-release desde candidato con commits aprobados de los tres frentes.
Server original C:/My Projects/app dirty no tocar; integrar en worktree separado
desde C:/My Projects/control360i-seguimiento-ia, branch JuxnD/120-release.

Repoapp JuxnD/seguimiento. Main/live1.19 ce6898141d8040799f6fb70cb049df7b914df151,
Release37499977216 yCI37499905119 success verificados al inicio. No retag1.19.
Nueva pubspec1.20.0+28, tagv1.20.0 (verificar ausencia antes de crear).
Si cambió main/publicación por otro owner, reconciliar sin sobrescribir cambios.

## Integración y evidencia de producto

1. Cherry-pick solo commits revisados; conflictos dependen de intención/core,
no resolver aceptando un lado ciegamente. Incluir plans actuales, contexto actualizado
y COSTURAS para auth/foto/frase/etiqueta/catálogo/report snapshot/history/backup/
fuente cita→acción/DB→APK→release. README ya no afirma 'sin backend': sigue
local-first y gateway opcional explícito. Reconciliar docs comidasyroadmap/IA
(autorización pendiente previa ya satisfecha). Actualizar decisión/schema18 y
entregable de alcance todas funciones. Contexto mantiene mapping existente.
2. Flutter3.22 fijo C:/flutter-3.22-old/bin; Java17. flutter pub get;
dart run build_runner build --delete-conflicting-outputs; flutter analyze;
flutter test --timeout90s. Repetir solo fallos y cambios nuevos que lo justifiquen.
Construir APKrelease. La llave histórica NO se rota ni reemplaza.
Cert SHA2566f839c41abf9e17634544a8ae5dff18ca64333b070ef40cd582dbdc9ac133ed7.
3. Tests Android solo emulador propio Seguimiento_QA_119 port5580 (headless).
Nunca instalar/escribir en emulador5554 del owner ni teléfono diario. Oráculos
sintéticos: clipboard reread; foto corregir/descartar y guardar; frase2huevos
140kcal/12P deterministas; etiqueta30g150kcal/3P normaliza500kcal/10P con
confirmación; historial reabrir/reinicio/borrado/backupZIP17→18, preguntas
fuenteID, faltantesfecha histórica yguía segúncarga/agarre, cuota/reset/cancel.
Mocks solo frontera de diálogo sistema/proveedor; SQLite/migraciones/cálculos/
navegación y almacenamiento reales. Artefactos/frame360×800 texto1/1.6 con
fuentes versionadas; ningún Ahem. Nativepermisos/selectorcámara/galería siguen
como gates distinguidos del test que inyecta foto, no declararlos comprobados.

## Gateway deploy autorizado

Leer entero docs/DEPLOY.md. Commit limpio+push ramaaislada antes de deploy.
Preflight scripts/deploy-preflight.ps1 -CommitSHA -StagePathTemp -Fileslista
solo archivos runtime IA y dependencias nuevas. Backup SFTPactual y comparar
los dos archivos existentes con caf0b4bd normalizando EOL; nuevos deben estar
ausentes. Si drift investigar/no sobreescribir. Upload solo staging y servicio
dependencia antes Controller. Re-get cada archivo y comprobar SHA256 byte exacto.
SSH shell no disponible: SFTP usercontroli host69.175.121.50,
key~/.ssh/id_ed25519_control360i; remote public_html/app/<repo-relative-file>.
No subir settings, keys,fixtures,tests ni cambiosERP/Escriba. Verificar GD real
mediante capacidad autenticada de imagen; si falta no fingir foto/etiqueta lista.

Smoke login200,indexseguimiento200,legacyGET405/vacío400,nuevorutaPOSTinvalid400,
POSTrevoked403, wrongowner403, logs/cuota403HTTP. Test proveedorS0 con datos
SOLO FICTICIOS y licencia QA separada: previaQA15 fue revocada al terminar.
Si se reutiliza, verificar id/HWID/cuenta/datos privados y reactivar solo esa fila
bajo autorización vigente de pruebas; al cierre revocar y comprobar403. No
modificar licencias reales ni leer/extraer clave OpenAI. Credentialsgateway están
fueraGit ~/.ssh; no imprimirlas ni pegar datos personales en requests.
Probar weeklylegacy, meal_text con catálogo sintético, label con etiqueta sintética,
report/exercise pregunta con fuente ficticia y meal_photo con imagen sin comida
(debe abstenerse). Esto prueba contrato/visión/transporte, no exactitud nutricional.
Registrar tokens/latencia sin contenido/secretos si disponibles, sin convertirlo enROI.

## Publicación y verificación

Push rama integración (autorizado), PR coherente títulos/descriptionfunciones,
adjuntar siempre PR herramienta attach_artifact. CI exactSHA éxito, revisar diff;
merge bajo autorización user, detectar headraces. Tagv1.20.0 solo commitintegrado,
workflowRelease analiza/tests/firma/publica. Esperar con observación espaciada y
comentarios≤60s, no pollsunchangedfrecuentes. No subir APKlocal como verde siCI
falla; diagnosticar y reparar preservandoタグ publicada. Release no reetiquetar.

Descargar APK público nuevo, aaptname/code28, apksignercert igualhistórico,
SHA256 vsasset/cantidad bytes; instalar -r soloQA sobre1.19 para probarupgrade.
ConfirmarversiónActiva/abrir/noAndroidRuntimeerror; fuente→compilado→publicado→
releído es cadenaentera. Publicar release notes en español incluyendofunciones,
privacyconsentido/estimaciones,revisión,labelcheckbox, límite20/nointernetfallback.
No afirmar instalado en teléfono real ni aceptado clínicamente.

DONE implementaciones/aprobación/gatewayvalidado/release pública verificable,
contexto actualizado, QA temporal apagado y credenciales QA revocadas. Cierre
reporta implementación, validación operacional sintética y gates de uso real.
No detener por permission ya otorgado; sí declarar bloqueo externo real con
evidencia y trabajo completo restante si aparece. Asesor puede tomar deploy/release
tras revisión, no necesita delegarlo de nuevo.
