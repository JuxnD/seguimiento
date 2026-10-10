# Preparación de un piloto

Estado al 9-oct-2026: **PREPARACIÓN PARCIAL**. No PREPARADO_PARA_PILOTO todavía.
Caso y supuesto letal: [CASO.md](CASO.md). La delimitación del coordinador permite
privacidad, herramientas y documentación antes de 008–011; prohíbe activar alta
nueva, SDK, distribución o usuarios reales en este slice.

## Qué ya existe y qué falta

| Frente | Resultado / gate |
|---|---|
| Inventario de respaldo | UI declara base, historial IA y fotos; ZIP sin cifrar y licencia excluida. Confirmación antes de crear/compartir. |
| Borrado IA | Elimina la conversación de la base actual. UI explica que copias anteriores pueden recuperarla y que el servicio no se modifica. |
| Copias automáticas | UI declara historial IA, sin fotos, sin cifrar. No se purgan copias silenciosamente. |
| Gate de artefactos | Herramientas nuevas y pruebas sintéticas; faltan captura nativa del candidato integrado y conexión al workflow. |
| Perfil nuevo | **PENDIENTE**: no heredar datos del owner. Especificación debajo; no implementado ahora. |
| Progreso/comidas/gráficas | **PENDIENTE** integración y aceptación 008–011. |
| Figuras | Aceptación humana de comprensión pendiente; existencia del JSON no la sustituye. |
| Tienda | [Matriz](piloto-compatibilidad.md); spike target36/runtime no realizado. |
| Uso real | Sin participantes, baseline, umbrales ni agenda confirmados. |

## Contrato para alta nueva y legado

La primera apertura de una base nueva debe preguntar fecha de inicio y metas
necesarias, ofrecer una plantilla explicada y permitir cancelación sin datos
parciales. No copiar calendario, peso, mediciones, 27 entradas históricas ni
licencia del owner. La base de pasos es 5.000 según el motor 009.

La actualización del owner conserva su perfil, metas explícitas, plan,
historial y sesión congelada. Correcciones personales requieren procedencia
legacy demostrada o importación personal explícita; una tabla vacía no prueba
identidad. Restaurar una base legacy conserva recuperación y pregunta antes de
reemplazar. Faltan pruebas de alta/reinicio/restauración/cancelación/error y dos
perfiles ficticios independientes; no habrá migración incidental desde este slice.

## Datos y retención

La verdad es el formato implementado por BackupArchive y DatabaseHost:
SQLite completa más fotos referenciadas en ZIP v1, sin cifrado del archivo.
Incluye contexto y conversaciones IA si existen. Exportar no prueba que el
destino guardó el archivo. La activación cifrada está en Android noBackupFilesDir,
fuera de SQLite/ZIP. Los flags y el cronómetro no se exportan ni reemplazan.

Eliminar IA no cambia respaldos automáticos anteriores ni archivos externos,
y no llama a un borrado remoto. No se añadió purga local ni cifrado de ZIP:
serían decisiones separadas con restauración compatible y selección explícita.
La [política Android016](adr/0018-arranque-y-respaldo-android.md) configura
exclusión de cloud y trasladoD2D automático en Manifest y reglas legacy/31+.
ZIP manual y copias locales se conservan. Parser fuente/mutantes y UI no prueban
el respaldo del sistema: quedan Manifest fusionado y transporte del APK exacto
en dispositivoQA. No se afirmó que el teléfono del owner subiera datos ni se
eliminan copias previas o controlan herramientas del fabricante/terceros.

## Ensayo end-to-end antes de voluntarios

Alta nueva → plato desconocido → porción/dudas → revisión/guardar → entrenamiento
→ decisión adaptativa → gráfica/radar → IA/borrado → exportación → restauración
→ reapertura. Dataset ficticio congelado, sin credenciales reales prestadas.
Cada paso exige evidencia de UI y relectura de SQLite/archivos. El APK instalado
es el mismo hash que el candidato y se actualiza sin desinstalar la base pública.
El guion pausado conserva dosis/índice al reanudar y reabrir.

Preparación completa exige: alta aislada, 008–011, comprensión de figuras,
continuidad sintética con APK exacto, política de datos y caso viable acordados.
La propia app del owner y su teléfono no están validados por ese ensayo.

## Medidas que se deben recoger

| Medida | Fuente / denominador | Estado actual |
|---|---|---|
| Tiempo de registro | Tareas comparables manual/IA; mediana y rango incluyendo corrección | NO_MEDIDO |
| Cobertura de componentes | Corpus etiquetado; componentes cubiertos, omitidos y dudas explícitas | NO_MEDIDO |
| Correcciones de porción/macros | Propuesta y valor revisado; receta/peso/etiqueta de referencia | NO_MEDIDO |
| Comprensión de recomendación/radar | Explicación de evidencia, acción y límite por participante | NO_MEDIDO |
| Continuidad de uso | Días con registros y días observados; faltantes separados de cero | NO_MEDIDO |
| Coste por tarea útil | Tokens/factura, latencia y respuestas aceptadas, incluido reintento | NO_MEDIDO |
| Preservación de datos | Todos los valores/archivos del manifest de cada upgrade/restore | Herramienta probada; candidato nativo PENDIENTE |

Owner y facilitador deben fijar umbrales y respuesta al fallo antes de medir.
No habrá puntuación clínica, precisión universal ni ahorro inventados desde una
muestra pequeña. Piloto no prueba demanda de mercado. Distribución comercial
requiere decisiones reales de soporte, privacidad, datos de salud, términos y
tienda; este documento no certifica cumplimiento legal.

## Recibo y compuerta de publicación

Procedimiento/contrato: [runbooks/pilot-release-gate.md](runbooks/pilot-release-gate.md).
Las herramientas no crean capturas ni ejecutan ADB: comparan artefactos
extraídos del AVD propio con expectativas congeladas, releenlos y contrastan
APK/firma/versiones mediante herramientas Android. La procedencia de la captura
requiere revisión del runner/operador; un manifest autodeclarado no atestigua un
dispositivo. Tests con mocks o fixtures nunca reemplazan QA nativa.

No se cambió workflow ni publicó APK. Cada candidato necesita nuevo recibo;
los recibos anteriores no prueban otro archivo o commit.
