# IA útil en el uso diario

6 oct 2026. Evidencia del owner: los comentarios responden en su teléfono,
pero solo podía verlos; escribir comidas manualmente le resulta incómodo.
La captura demuestra uso del copiloto, no exactitud de sus conclusiones ni
el número de versión instalado.

## Publicado en 1.20.0+28

- Comentarios: seleccionar texto, copiar la respuesta o un comentario con su
  cita, compartir mediante el selector del sistema. No exporta licencia,
  identificador ni informe completo. No envía mensajes por sí solo.
- Comidas → Nueva comida → **Registrar con foto · IA**. Cámara/galería,
  vista previa, consentimiento por foto, propuesta, quitar alimentos y
  multiplicar porciones, **Añadir al borrador**, corregir cifras en el
  formulario y **Guardar**. Cancelar/salir no crea comidas ni alimentos.
- Todos los macros de foto son estimados (`sourceVerified = null`, sin
  referencia de catálogo). Se conservan porciones asumidas e incertidumbres
  en notas. La imagen no mide gramos ni revela ingredientes ocultos.
- Imagen transitoria reencodificada a PNG, sin EXIF, hasta 1024 px y 2 MiB.
  No se guarda ni entra al respaldo. No sale hasta aceptar el envío.
- Reutiliza activación Keystore y gateway de Control360i, nunca una clave de
  OpenAI en APK. Endpoint nuevo `/seguimiento/comida`, mismo dueño/canal/cuota.
  Servidor y app validan límites/coherencia de salida. Cifras plausibles no
  implican exactitud nutricional.

El owner autorizó todas las oportunidades de esta tabla para 1.20 después de
Improve. Están publicadas: [frase y etiqueta](ia-comidas.md),
[preguntas, guías e historial](ia-informes.md), [decisión común](adr/0012-asistente-por-tareas-y-fuentes-locales.md).
El gateway está publicado y leyó los valores impresos de dos etiquetas
sintéticas, una mayor de 1 MB. El APK público firmado pasó actualización en QA
sin perder registros ([recibo](context/sessions/2026-10-06-entrega-120.md)). Falta
piloto en el teléfono. Las pruebas sintéticas no validan reconocer una comida real.

## Funciones incluidas en 1.20

| Prioridad | Función propuesta | Valor y condición de aceptación |
|---|---|---|
| 1 | Comidas por foto con revisión | Reducir escritura; aceptar solo si revisar/corregir tarda menos que registrar manualmente. Ya hay candidato. |
| 2 | Registro por frase: «dos huevos, arroz y pollo» | Proponer alimentos del catálogo y pedir solo la cantidad que falte. Macros calculados localmente, confirmación única. El dictado del teclado puede aportar voz sin otra API. |
| 3 | Historial local y preguntas sobre informes | Reabrir análisis con fecha/rango y preguntar «¿qué cambió frente a la semana anterior?». Respuestas con citas y cálculos locales; elegir contexto antes de enviarlo. |
| 4 | Convertir datos faltantes en accesos | Desde «falta peso» abrir pesaje; desde comida incompleta abrir el día. Se puede implementar de forma determinista sin consumir otra consulta. |
| 5 | Leer etiquetas nutricionales | Foto de empaque → valores por 100 g o por porción → borrador del catálogo. Exigir comprobar tamaño de porción, unidades y etiqueta; nunca marcar verificado automáticamente. |
| 6 | Explicar un ejercicio usando su guía | Consultar dudas sobre pasos/equipo ya documentados. Vincular figura y guía; no evaluar lesiones ni prometer corregir técnica a partir de una foto. |

Evitar un agente general que cambie metas, dieta o plan automáticamente. La
utilidad inmediata está en preparar registros y volver accionables los datos
existentes. Recomendaciones anteriores son propuestas, no beneficios medidos.

## Piloto y límites de evidencia

Adoptante: owner que usa Seguimiento diariamente. Dolor confirmado por su
petición; minutos ahorrados y exactitud siguen sin medir. Supuesto a refutar:
revisar un borrador de foto resulta más rápido y claro que introducirlo a mano.
Piloto propuesto: comparar ambos flujos en cinco comidas habituales, medir
tiempo completo y correcciones, incluyendo aceite/salsas y porciones ambiguas.
No se ha acordado fecha ni se declara ahorro o éxito operacional.

GPT-6 Luna admite imágenes como entrada y texto como salida según
[OpenAI Docs](https://developers.openai.com/api/docs/models/gpt-6-luna).
El envío utiliza `input_image` en Responses con imagen base64, conforme a
[Images and vision](https://developers.openai.com/api/docs/guides/images-vision).
Las limitaciones visuales y las porciones desconocidas obligan a mantener la
estimación y la revisión. Este candidato no usa audio ni herramientas del modelo.
