# Comidas por foto como borrador estimado

Fecha: 6 oct 2026. Estado: aceptada para candidato local; despliegue pendiente.

El owner pidió registrar comida mediante fotos y aprovechar las respuestas
de IA. El core existente ya guarda comidas, congela macros y distingue cifras
estimadas de etiquetas/referencias. Se reutiliza ese core sin migración de BD.

Una foto puede proponer alimentos, porciones y macros aproximados. El servidor
devuelve una estructura acotada, sin herramientas ni escritura; la app muestra
incertidumbres y permite quitar/cambiar porciones. Solo una confirmación añade
al borrador y el Guardar habitual persiste. Los ítems nacen como entradas
libres estimadas; no se vinculan a un alimento verificado por similitud de nombre.

No se introduce una base externa de alimentos. No se crean automáticamente
alimentos del catálogo. No se conserva la imagen original; se envían píxeles
reencodificados sin EXIF bajo consentimiento propio de esa foto. Reutilizar la
pantalla de fotos corporales mezclaría finalidades y queda descartado.

Consecuencias: origen/porciones/limitaciones se conservan como notas, no como
gramos medidos. El usuario puede corregir macros en la entrada libre existente.
Guardar fotos como diario, preservar análisis y reconocer etiquetas son features
posteriores. Un control de límites/coherencia protege el contrato, no demuestra
verdad nutricional. Se requiere piloto de utilidad antes de llamar exitoso al flujo.
