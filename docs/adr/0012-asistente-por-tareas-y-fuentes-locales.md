# 0012 — Asistente por tareas y fuentes locales

Decisión: 6 oct 2026. Alcance autorizado por el owner tras ejecutar Improve.
Estado de entrega y evidencia: [índice de contexto](../context/INDEX.md).

## Contexto

El copiloto semanal ya responde en el teléfono del owner. Hace falta poder
utilizar sus respuestas, reducir la escritura de comidas y preguntar sobre
registros y guías sin crear otra fuente de verdad ni perder la revisión humana.

## Decisión

Reutilizar Control360i y el canal existente, con la clave del proveedor en el
servidor y la licencia cifrada por Keystore. Las tareas nuevas comparten el
contrato v2; las rutas semanales y de foto mantienen compatibilidad con 1.19.
Cada consulta presenta su contexto y exige consentimiento. El transporte tiene
plazo total y tamaño acotados, sin reintentos automáticos. Consultar estado,
reabrir historial y abrir formularios no llaman al modelo.

- Foto de comida: propuesta estimada, editable y transitoria. Corregir o salir
  del borrador no escribe alimentos ni convierte una estimación en etiqueta.
- Frase: el modelo propone identificadores del catálogo y cantidades; los
  macros los calcula el dominio local. Una unidad incompatible o cantidad
  desconocida requiere revisión explícita. Cada alimento se resuelve o se quita.
- Etiqueta: valores y base leídos, conservando desconocidos. La conversión por
  100 g/ml es local y explícita. La lectura sigue sin verificar hasta que el
  usuario compruebe los valores y la porción contra el empaque.
- Informes: fuente exacta elegida, comparación adicional calculada localmente y
  seleccionada antes de enviarla. Los accesos a faltantes salen de datos locales
  y destinos tipados con fecha visible; abrirlos no crea registros.
- Ejercicios: reutilizar la guía real con su variante, agarre y claves
  personales. El enlace a la guía se resuelve localmente, sin rutas generadas
  por el modelo ni envío de fotos corporales.

El historial pertenece a SQLite (esquema 18): fuentes inmutables con hash,
fecha/rango, modelo, versión del contrato, preguntas, respuestas y citas. Se
crea sólo con respuestas que superan los controles. Las citas se comprueban
contra la fuente indicada; eso no acredita la veracidad de la interpretación.
No guarda licencia, HWID ni imágenes transitorias. Los respaldos de SQLite
incluyen el historial; el ZIP manual también conserva las fotos existentes.

## Consecuencias y límites

La cuota compartida es de veinte intentos por cuenta y día UTC y cien globales,
con saldo y reinicio visibles. Un fallo del proveedor puede consumir un intento;
cancelar evita aceptar una respuesta tardía, no garantiza evitar su facturación.
El modelo no modifica metas, plan ni registros. El usuario decide qué guardar.

Las pruebas sintéticas acreditan los contratos, la persistencia y las rutas de
revisión. La utilidad y la estimación de comidas reales se evalúan con el owner,
comparando el tiempo completo de revisión con el registro manual; no se presume
ahorro a partir del número de pruebas o de llamadas.
