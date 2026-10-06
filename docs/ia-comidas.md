# Registro de comidas con asistencia de IA

La entrada por frase y la lectura de etiquetas preparan propuestas temporales. Ambas vuelven al flujo local existente y no guardan una comida ni un alimento hasta que la persona use **Guardar** en su formulario. Cancelar una consulta o una revisión descarta la propuesta.

## Describir una comida

La pantalla envía, con consentimiento ligado al texto actual, una frase de hasta 2.000 caracteres y hasta 200 filas reducidas del catálogo (`id`, nombre, base, unidad y cantidad habitual). No envía macros ni el historial. El teclado puede dictar la frase; la función no pide permiso de micrófono ni envía audio.

El resultado permite como máximo ocho propuestas. Un ID debe pertenecer al catálogo enviado. El cliente acepta cantidades finitas entre 0 y 5.000 o `null`; solo preselecciona una cantidad positiva si la unidad coincide exactamente con la unidad del alimento local. Si falta el ID, la persona elige un alimento del catálogo; si falta la cantidad, puede escribirla o confirmar explícitamente la cantidad habitual. Una unidad incompatible deja la cantidad en blanco. Para agregar, cada propuesta debe quedar resuelta o quitarse de forma explícita; no se descartan filas ambiguas al aceptar otras.

Los macros se calculan localmente desde el alimento seleccionado. La pantalla devuelve el mismo tipo de borrador de comida que el registro manual; fecha, franja, hora, notas e ítems que ya estaban en el formulario se conservan. El borrador no se persiste hasta **Guardar**.

## Leer una etiqueta

La foto se recodifica a PNG sin metadatos, limitada a 1.024 px y 2 MiB para el envío. Solo se transmite después del consentimiento para esa foto. No se conserva en un campo de base de datos ni se incluye en copias de respaldo.

El resultado conserva los valores leídos como `null` cuando faltan y mantiene una copia de la base, unidad, tamaño de porción e incertidumbres originales. La conversión local de una porción a valores por 100 g/ml usa `valor × 100 ÷ cantidad de la porción`; el modelo no transforma cifras. Una cifra expresada solo en kJ no se convierte a kcal.

La pantalla abre el editor normal de alimentos con una propuesta transitoria. Si la base no se identificó, se debe elegir **Por unidad** o **Por 100 g/ml**; una unidad faltante se debe escribir. Si se leyó “por porción” pero no el peso, se requiere confirmar el uso de una unidad llamada “porción” sin conversión a g/ml y establecer su cantidad por defecto. Los cuatro macros deben estar presentes y ser válidos para guardar. Sin la casilla **Comprobé valores y porción con el empaque**, la fuente queda como estimación; solo esa confirmación explícita permite marcarla como etiqueta verificada. Cancelar el editor no modifica el catálogo.

## Transporte y estado

Las tareas nuevas usan el cliente v2 común y su endpoint fijo `/app/seguimiento/asistir`, con las tareas `meal_text`, `food_label` y `status`. `status` no solicita una generación ni descuenta presupuesto. La foto de comida sigue usando su transporte legado; después de cualquier respuesta de esa consulta se relee el estado gratuito para mostrar la cuota reportada, sin inventar decrementos locales. Los estados de consulta de presupuesto están separados de las generaciones de análisis para que una respuesta tardía no habilite otra licencia.

No hay reintentos automáticos. La activación permanece en el almacenamiento seguro común; no se solicita ni persiste una clave de proveedor. Las respuestas inválidas, fallos HTTP, límite de consultas, desconexión y cancelación dejan el registro manual disponible.
