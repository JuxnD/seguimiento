# IA en Seguimiento · estado 6-oct-2026

El owner autorizó incluir pendientes en1.19 y pidió reutilizar la infraestructura de Escriba/FioraSoft en Control360i. El estado anterior aplazada/sin build autorizado queda sustituido por **cliente y gateway implementados; despliegue/activación/aceptación pendientes**. No se afirma que la IA opere en producción todavía.

## Uso y arquitectura

Informe → Analizar este informe con IA. Vista previa del texto exacto, consentimiento por consulta, licencia revocable propia de cada teléfono. Modelo fijo GPT-6 Luna. App envía solo informe seleccionado, no SQLite ni fotos. El usuario revisa comentarios y citas; IA no guarda ni cambia metas, plan, comidas o sesiones. SQLite/cálculos/informe siguen offline.

Escriba usa `/fiora/update/llave` para recibir la clave y guardarla mediante Windows DPAPI. Ese mecanismo no se traslada al móvil. Nuevo POST `/seguimiento/analizar`: autentica HWID+licencia ATLAS activa+cuenta dueña del canal, reutiliza la clave configurada **dentro del servidor**. Android almacena únicamente la licencia cifrada con Keystore en noBackupFilesDir, excluida de respaldos. Reinstalación exige nueva activación; restaurar datos no transfiere licencia.

Servidor propuesto: Control360i, canal existente bondo-estacion previa autorización específica. Rama aislada `JuxnD/seguimiento-ia`, checkout `C:\My Projects\control360i-seguimiento-ia`; especificación `docs/seguimiento-ia.md` allí. Ninguna ruta de Escriba/ERP se modifica. AGENTS.md del servidor exige aprobación explícita para despliegue; consulta pendiente al owner, separada de su autorización de publicar1.19.

## Límites y privacidad

Informe≤48KB; seis notas máx., quote literal verificable en informe, sin cifras nuevas fuera de cita; formato desconocido/refusal/incomplete se rechaza. Esto comprueba referencias y límites, **no garantiza veracidad semántica** ni seguridad clínica. Comentarios descriptivos, sin diagnóstico/prescripción. Es una propuesta para revisar, no una decisión automática.

Servidor conexión8s/respuesta40s, app50s; cancelar descarta respuesta tardía y cierra transporte, pero una llamada recibida puede facturarse. Sin reintento automático. Cuotas failclosed con bloqueo:4intentos por cuenta/día UTC y20globales; intento fallido consume cuota. Clave no va alAPK; licencia no se registra en logs ni paquetes. Servidor no conserva informes/respuestas, solamente contadores de uso. Responses API usa store=false. OpenAI puede retener registros de seguridad por defecto hasta30d, con excepciones legales/de seguridad; [política oficial](https://developers.openai.com/api/docs/guides/your-data), revisada6oct.

## Caso y gates

Dolor: copiar/pegar informe al chat interrumpe revisión semanal. Oportunidad: acceso dentro de app a comentarios con evidencia. Adoptante: owner que usa app a diario. Baseline de tiempo/utilidad no medida; no se promete ahorro. Supuesto crítico: respuesta útil y verificable con datos faltantes sin cambiar registros.

Pruebas técnicas con datos ficticios: cliente y consentimiento/cancelación; servicio y frontera HTTP de autenticación/cuenta/límites. Pendientes: autorización de deploy del servidor, licencia específica del teléfono, S0 sintético contra modelo real, relectura de bytes/HTTP de producción y aceptación de utilidad. Ventana propuesta dos semanas, sin compromiso de fecha del owner. Un resultado sintético no demuestra aceptación cotidiana ni validación médica.

Después del S0/activación, el usuario decide enviar sus registros en cada consulta. Fotos/comidas por IA, nube y escritura automática permanecen fuera de esta versión.
