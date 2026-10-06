# Copiloto semanal de IA — estado y activación

Actualizado el 6 oct 2026. El owner autorizó incluir pendientes en 1.19 y desplegar y activar el gateway de Control360i. Sustituye el estado anterior «aplazada, sin build autorizado».

**Implementado:** cliente en 1.19.0+27 y gateway publicado. Consulta real a GPT-6 Luna verificada con informe ficticio desde Windows y Android. La captura del owner del 6 oct confirma comentarios en el teléfono diario; no se inspeccionó su versión instalada. **Pendiente:** aceptación de utilidad. La licencia de QA fue desactivada y el servidor confirmó 403; las licencias anteriores permanecen intactas.

## Cómo se usa

Informe → **Analizar este informe con IA**. Vista previa del texto exacto, política de datos y consentimiento para enviarlo. Solo salen el informe elegido y la activación: no SQLite ni fotos. Los comentarios llevan citas y son propuestas para revisar; no cambian plan, metas, comidas, registros ni cálculos locales.

Para activar otro teléfono: copiar su identificador `SEG-…`, crear su licencia en **Control360i → ATLAS** dentro de la cuenta propietaria del canal `bondo-estacion` y escribirla en la app. No reutilizar la identidad/licencia de Escriba. Se revoca desde ATLAS. Android cifra la licencia con Keystore en `noBackupFilesDir`, fuera de respaldos; reinstalar requiere activación nueva.

## Arquitectura y límites

Escriba recibe la clave mediante `/fiora/update/llave` y la cifra con DPAPI. Seguimiento usa POST `/seguimiento/analizar`: valida licencia activa, identificador y cuenta propietaria; la clave existente permanece en el servidor. No se alteraron rutas de Escriba ni ERP.

Gateway inicial 1.19: `caf0b4bd`, dos archivos nuevos con relectura SHA-256.
Gateway ampliado para 1.20: `f107763a`, rama aislada `JuxnD/120-release` de
Control360i, cinco runtimes re-leídos e idénticos al staging. Las rutas previas
conservan contrato; las tareas nuevas usan `/seguimiento/asistir`.
Especificaciones en `docs/seguimiento-ia.md` y `docs/seguimiento-ia-v2.md` de ese repo.

Modelo fijo `gpt-6-luna`, sin herramientas ni SQL. Informe máximo 48 KB, seis notas, citas literales y ningún dígito nuevo fuera de citas. Rechaza formato inválido, negativa del modelo y respuesta incompleta. Estos controles verifican referencias, **no garantizan veracidad semántica ni validez clínica**. Comentarios descriptivos, sin diagnóstico ni prescripción.

Cuota compartida con bloqueo y fallo cerrado: veinte intentos por cuenta/día
UTC, cien globales. La app muestra saldo y reinicio; consultar status y abrir
historial no llaman al modelo. Fallos consumen intento; sin reintento automático.
Servidor: conexión 8 s, respuesta 40 s; app: 50 s. Cancelar cierra transporte y
descarta respuestas tardías, pero una llamada recibida puede facturarse.

Servidor conserva contadores y códigos de diagnóstico, sin informes/respuestas/claves/licencias en logs; acceso HTTP a esos archivos devolvió 403. Responses usa `store=false`. OpenAI conserva registros de seguridad normalmente hasta 30 días, con excepciones legales o de seguridad: [política oficial](https://developers.openai.com/api/docs/guides/your-data).

## Evidencia inicial de 1.19 y aceptación

Controles locales de validación, consentimiento, cancelación y errores; 16 controles PHP y ocho HTTP local. S0 publicado devolvió cinco notas coherentes, con todas sus citas verificadas. Android comprobó cifrado/lectura/borrado de licencia y consulta HTTPS al gateway real. Ninguna prueba envió registros personales ni fotos.

Caso: evitar copiar informe al chat. Adoptante: owner que usa la app diariamente. Baseline de tiempo/utilidad sin medir; no se declara ahorro ni ROI. Propuesta de aceptación: dos semanas comparando utilidad/correcciones con el flujo anterior, sin fecha comprometida. Informe local disponible sin internet.

## 1.20 publicada: asistente por tareas

Copiar/compartir cada comentario o respuesta completa, conservando citas, y
selección de texto. La exportación no contiene licencia, HWID ni informe completo.

La comida por foto usa otra pantalla y otro consentimiento: solo imagen elegida,
reencodificada sin EXIF, resolución/peso acotados y activación. No SQLite,
historial ni fotos corporales. Endpoint publicado `/seguimiento/comida` con la
misma autorización/cuota. Propuesta estimada → revisión → borrador → Guardar;
no se crean registros automáticamente. No conserva imagen ni cambia el backup.
[Especificación y oportunidades](ia-oportunidades.md), [ADR](adr/0011-comidas-foto-como-borrador-estimado.md).

Todas las oportunidades están publicadas en 1.20.0+28. El gateway
publicado leyó dos etiquetas ficticias, una mayor de 1 MB; Android comprobó
preparación de foto, envío y lectura contra el proveedor real. La licencia QA
se revocó de nuevo y status devolvió 403. No se afirma exactitud con comidas reales.
[APK, firma y conservación de datos verificados](context/sessions/2026-10-06-entrega-120.md).
El 6 oct el owner autorizó todas las oportunidades propuestas, incluidas las
que estaban diferidas, y su publicación en una nueva versión. También está
vigente su autorización explícita de despliegue en Control360i/canal
`bondo-estacion`. Se ejecutó Improve antes de implementar; el alcance y los
controles de entrega están en [plans](../plans/120-improve-audit.md). Esta
autorización se ejecutó y quedó verificada en la publicación 1.20.0+28,
como consta en el recibo de entrega.
