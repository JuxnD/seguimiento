# Preguntas locales sobre informes y guías

Las preguntas sobre el informe y sobre una guía reutilizan el gateway de IA
existente y el flujo común de activación y presupuesto. Antes de enviar, la app
muestra el texto de las fuentes y una vista previa de la consulta; cada pregunta
requiere consentimiento. Las preguntas usan como máximo dos fuentes y limitan
el contexto a 48.000 bytes. El historial enviado queda limitado a cuatro pares
y 4.000 caracteres. Si el contexto excede el límite, se pide elegir un rango
más corto en vez de truncarlo.

Para un informe, la fuente actual es exactamente el texto que la app muestra y
permite copiar para el rango elegido, incluidos los registros presentes allí.
La app pregunta de forma explícita antes de adjuntar una segunda fuente con la
comparación del periodo previo calculada localmente. No se envían fotos. Una respuesta nueva debe
tener entre una y seis citas exactas, atribuibles a una fuente guardada. Las
respuestas del contrato 2 se limitan a 1.500 caracteres y no pueden añadir
cifras fuera de las citas. Una respuesta inválida, fallida o cancelada no se
guarda. La conversación se crea solo después de validar la respuesta; continuar
una conversación vuelve a comprobar sus citas contra el snapshot persistido.

El historial vive en SQLite local y forma parte del ZIP portable. Cada
conversación conserva el JSON exacto de sus fuentes, hash SHA-256, tipo, título,
rango, modelo y versión del contrato; cada turno conserva su modelo, versión y
citas. Las conversaciones pueden borrarse desde Historial. La interfaz muestra
el límite de veinte preguntas por conversación y no elimina registros antiguos
de forma automática.

Las acciones de completar datos son propuestas locales tipadas por clase y
fecha; nunca se infieren de texto generado por IA. Abrirlas lleva al formulario
existente y no escribe el registro hasta que el usuario lo guarda. Las acciones
de pasos solo apuntan a días entre semana sin dato. Las comidas cerradas no se
marcan como incompletas. La pregunta desde una guía usa la carga, agarre, claves,
variantes y progresión de la misma guía renderizada; no envía fotos.

## Validación

- `test/domain/ai_report_sources_test.dart` comprueba comparación local y
  exclusión de datos corporales.
- `test/domain/missing_data_actions_test.dart` comprueba acciones fechadas,
  días cerrados y ausencia de fechas futuras.
- `test/data/ai_conversation_repository_test.dart` comprueba hash, citas,
  creación perezosa, límite visible y borrado en cascada.
- `test/data/migration_test.dart` y `test/data/backup_archive_test.dart`
  comprueban la migración de la fixture independiente 17 y el ZIP portátil.

El uso desde un teléfono, el render final y cualquier aceptación de producto
siguen siendo gates separados de las pruebas de código.
