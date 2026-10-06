# Improve · alcance consolidado de Seguimiento 1.20

Auditoría estándar, 6-oct-2026. Fuente app0e3855c (candidato), gateway9f1981cf
(candidato); producción app1.19 ce68981/gatewaycaf0b4bd. Owner autorizó todas
las oportunidades anteriores, implementación y publicación; pidió auditar primero.
Tres revisores independientes, playbook Improve; todos read-only. El asesor
confirmó cada referencia material en fuente antes de redactar estos planes.

## Hallazgos confirmados y orden

| # | Hallazgo | Categoría | Impacto | Esfuerzo | Riesgo | Confianza / evidencia |
|---|---|---|---|---|---|---|
| 1 | Corregir foto escribe catálogo antes de Guardar | Bug introducido | Cancelar puede crear/modificar alimentos | M | Medio | Alta: meal_form_screen.dart97,222; nutrition_repository.dart189 |
| 2 | Coincidencia de nombre/macros convierte foto a etiqueta | Bug introducido | Informe pierde incertidumbre | S | Bajo | Alta: meal_form_screen.dart190; nutrition_repository.dart29 |
| 3 | Informe no observa sueño/fecha | Bug previo | IA puede recibir registros obsoletos | S | Bajo | Alta sueño, media fecha: providers.dart315–327; report_repository.dart133,180 |
| 4 | Notas de porciones originales aparentan cifras finales | Bug introducido | Corrección produce evidencia contradictoria | M | Medio | Alta: meal_photo_screen.dart159–164; meal_form_screen.dart99,236 |
| 5 | Clientes/copias de transporte y booleano de servidor | Arquitectura | Cuatro modalidades nuevas multiplicarían divergencias | L | Medio | Alta: weekly_ai.dart37; meal_photo_ai.dart93; seguimientoController.php26 |
| 6 | Cuota4 compartida y errores503 ambiguos | Contrato/producto | Agotar el día impide chat/etiqueta/guía; mala recuperación | M | Medio | Alta: SeguimientoAiService.php118; weekly_ai.dart57 |
| 7 | HTTP sintético nunca cruza proveedor/200 | Pruebas | Falta control de parse/negativa/timeout y cuota en costura | M | Medio | Alta: seguimiento_ai_http_fixture.php18; servicio153 |
| 8 | PHP codepoints y Flutter UTF16 difieren | Contrato | Salida válida del servidor rechazada en app por Unicode | S | Bajo | Alta: servicio44 y meal_photo_ai.dart150; negativo60emoji |
| 9 | Historial de IA no existe; fixture17 usa esquema actual | Datos/pruebas | Pérdida de resultados y falso verde de migración al18 | L | Medio | Alta: weekly_ai_screen.dart23; database.dart54; migration_test.dart86–91 |
| 10 | Firma de comidas sólo incluye ID/cantidad de ítems/kcal y observa sólo rango actual | Bug previo | Editar proteína/notas sin cambiar kcal, o corregir el período anterior, puede dejar informe/comparación obsoleto | S | Bajo | Alta: providers.dart `mealsRangeRefreshProvider` y dependencias de `reportInputProvider` |

Las referencias de app son relativas a lib/features, lib/data o lib/app según
el archivo; las de servidor a app/services, app/controllers y scripts. Cada plan
incluye rutas exactas y comandos independientes para ejecutores.

## Dirección autorizada, separada de defectos

Consolidar en tres frentes, conservando todas las funciones:
1. Gateway/activación/presupuesto comunes, contratos acotados por tarea.
2. Comidas: foto o frase → propuesta editable → formulario → Guardar;
   etiqueta → valores leídos/base/porción → revisión humana → catálogo.
3. Informes/guía: snapshot local → comentarios/preguntas con citas → copiar,
   compartir, reabrir/borrar; faltantes → accesos deterministas con fecha.

Propuestas adicionales de Improve: activación directa desde cada flujo,
presupuesto visible y recuperación de análisis sin nueva consulta. Se incluyen
porque completan las funciones autorizadas. Reusar comidas corregidas mediante
«Repetir de ayer» ya existe; no crear un catálogo/recetario paralelo.

## Considerado y rechazado

- Citas literales y texto sin dígitos no son bugs: limitan el modelo a describir
  evidencia. Comparaciones numéricas se calculan en el dominio local.
- store=false/clave en servidor/Keystore están implementados; no hay evidencia
  de filtración ni autorización rota en esta superficie. No rotar claves por rutina.
- Una cabecera PNG sin píxeles pasa el control actual, documentado. Endurecer
  decodificación limitada; no inventar SSRF/ejecución de código observada.
- No migrar Flutter ni incorporar otra base nutricional para esta entrega.
- No evaluaciones clínicas, agentes que escriban solos ni fotos corporales enviadas.

## Límites de auditoría

Cobertura ponderada hacia IA/nutrición/informe/backups y sus callers; no es una
auditoría nueva de todos los cronómetros, cada figura3D, ERP o proveedores externos.
No se probó calidad nutricional con comidas reales ni acceso del hosting a GD.
Los tests existentes prueban interfaces, no exactitud semántica del modelo.

## Ejecución

Owner ya seleccionó todo el alcance previo; no requiere repetir selección.
Planes001→(002,003)→004. Cada ejecutor trabaja en su worktree y se revisa su diff.
Publicación solo tras relectura de artefactos, firma histórica, gateway y CI/release.

## Revisión de implementación001 (primer pase)

Cliente792abd8 y cobertura e160b5d aprobados: asesor reejecutó17data+2UI y análisis.
Servidor6025c4b reproducido con32+16+148controles y33HTTP; arquitectura/auth/citas/GD
y transporte compartido comprobados. Revisor independiente encontró dos casos
introducidos: fuenteID repetido sobrescribe la primera; unidadtaza con catalog.g
mantiene quantity1 sin confirmar. REVISE1: rechazar IDs duplicados y dejar cantidad
pendiente ante unidad distinta (o rechazar); añadir negativos red/green y200legacy
cruzando payload/decoder/validator enfixture realController. Sin cambioAPIapp.

## Consolidación e integración verificadas

Los planes 001/002/003 están integrados en `JuxnD/120-release`; las revisiones
cerraron pertenencia de IDs, unidad incompatible, cuota de errores, fuentes
inmutables, base desconocida, edición sin catálogo y accesos vigentes en historial.
El asesor repitió 538 pruebas (14 capturas opcionales omitidas), análisis limpio,
12 capturas explícitas, flujos Android con relectura SQLite/ZIP y lectura de
etiqueta preparada en Android contra el proveedor real, siempre con datos ficticios.
El hosting sí cuenta con GD: dos etiquetas sintéticas pasaron, incluida >1 MB.
Esto actualiza el límite anterior de la auditoría, no acredita calidad con comida real.

Planes 005 y 006 cerrados técnicamente: preflight con includes y orden comprobado;
multipart JSON escalar evita el temporal no escribible sin disminuir la imagen
ni reintentar. Backend final f107763a con relectura de cinco runtimes. Probe
retirado (404), log protegido (403), QA revocada (403). Plan 004 continúa con
CI, release pública, firma/versión y conservación de registros al actualizar.
Recibo: [integración](../docs/context/sessions/2026-10-06-integracion-120.md).
