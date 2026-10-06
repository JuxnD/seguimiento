# Copiloto semanal de IA — estado y activación

Actualizado el 6 oct 2026. El owner autorizó incluir pendientes en 1.19 y desplegar y activar el gateway de Control360i. Sustituye el estado anterior «aplazada, sin build autorizado».

**Implementado:** cliente en 1.19.0+27 y gateway publicado. Consulta real a GPT-6 Luna verificada con informe ficticio desde Windows y Android. **Pendiente:** licencia del teléfono de uso diario y aceptación de utilidad. La licencia de QA fue desactivada y el servidor confirmó 403; las licencias anteriores permanecen intactas.

## Cómo se usa

Informe → **Analizar este informe con IA**. Vista previa del texto exacto, política de datos y consentimiento para enviarlo. Solo salen el informe elegido y la activación: no SQLite ni fotos. Los comentarios llevan citas y son propuestas para revisar; no cambian plan, metas, comidas, registros ni cálculos locales.

Para activar otro teléfono: copiar su identificador `SEG-…`, crear su licencia en **Control360i → ATLAS** dentro de la cuenta propietaria del canal `bondo-estacion` y escribirla en la app. No reutilizar la identidad/licencia de Escriba. Se revoca desde ATLAS. Android cifra la licencia con Keystore en `noBackupFilesDir`, fuera de respaldos; reinstalar requiere activación nueva.

## Arquitectura y límites

Escriba recibe la clave mediante `/fiora/update/llave` y la cifra con DPAPI. Seguimiento usa POST `/seguimiento/analizar`: valida licencia activa, identificador y cuenta propietaria; la clave existente permanece en el servidor. No se alteraron rutas de Escriba ni ERP.

Gateway: rama `JuxnD/seguimiento-ia` de Control360i; código publicado `caf0b4bd`, dos archivos nuevos con relectura SHA-256 verificada. Especificación/recibo en `docs/seguimiento-ia.md` de ese repo.

Modelo fijo `gpt-6-luna`, sin herramientas ni SQL. Informe máximo 48 KB, seis notas, citas literales y ningún dígito nuevo fuera de citas. Rechaza formato inválido, negativa del modelo y respuesta incompleta. Estos controles verifican referencias, **no garantizan veracidad semántica ni validez clínica**. Comentarios descriptivos, sin diagnóstico ni prescripción.

Cuota con bloqueo y fallo cerrado: cuatro intentos por cuenta/día UTC, veinte globales. Fallos consumen intento; sin reintento automático. Servidor: conexión 8 s, respuesta 40 s; app: 50 s. Cancelar cierra transporte y descarta respuestas tardías, pero una llamada recibida puede facturarse.

Servidor conserva contadores y códigos de diagnóstico, sin informes/respuestas/claves/licencias en logs; acceso HTTP a esos archivos devolvió 403. Responses usa `store=false`. OpenAI conserva registros de seguridad normalmente hasta 30 días, con excepciones legales o de seguridad: [política oficial](https://developers.openai.com/api/docs/guides/your-data).

## Evidencia y aceptación

Controles locales de validación, consentimiento, cancelación y errores; 16 controles PHP y ocho HTTP local. S0 publicado devolvió cinco notas coherentes, con todas sus citas verificadas. Android comprobó cifrado/lectura/borrado de licencia y consulta HTTPS al gateway real. Ninguna prueba envió registros personales ni fotos.

Caso: evitar copiar informe al chat. Adoptante: owner que usa la app diariamente. Baseline de tiempo/utilidad sin medir; no se declara ahorro ni ROI. Propuesta de aceptación: dos semanas comparando utilidad/correcciones con el flujo anterior, sin fecha comprometida. Fotos por IA, comidas y escritura autónoma quedan para evaluación posterior. Informe local disponible sin internet.
