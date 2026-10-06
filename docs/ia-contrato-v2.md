# Gateway de IA: contrato v2 del cliente

La app conserva los adaptadores actuales `/analizar` y `/comida` para la versión
1.19.0+27. Ambos usan el mismo transporte HTTP acotado, sin reintentos, timeout
de 50 s y límite de respuesta de 32 KiB. El cliente v2 se usa para tareas nuevas
y siempre envía a `https://www.control360i.co/app/seguimiento/asistir`.

## API Dart

```dart
final gateway = AiGatewayClient(http.Client());
final result = await gateway.assist(
  task: 'report_question',
  input: {'question': question, 'sources': sources, 'history': history},
  hwid: hwid,
  license: license,
);
final quota = gateway.lastQuota;
```

`assist` hace un solo POST con `contract: 2`, `task`, `input`, `hwid` y
`license_key`. Devuelve el mapa `result` solamente si el envelope confirma
`status: success`, contrato 2, la tarea solicitada y `model: gpt-6-luna`.
`AiError` contiene un mensaje saneado y, si el servidor reporta una cuota válida
en un 429, `code` estable y `quota`. `lastQuota` cambia en una respuesta exitosa
válida o en un 429 con cuota válida. Cada consumidor crea y cierra su propio
`http.Client`; al cancelar, cierra ese cliente. No se envían encabezados con
claves del proveedor.

El JSON UTF-8 menor que 16.384 bytes usa application/json. Desde ese tamaño,
el mismo JSON se envía como el único campo escalar `payload` de multipart,
sin archivos ni reintentos. El alojamiento no permite escribir su temporal
de PHP y pierde los cuerpos crudos grandes. Este formato conserva imagen,
Unicode, contrato y límites; se comprobó con un PNG ficticio de más de 1 MB.
El gateway admite ambos formatos y rechaza campos adicionales y archivos.
El controller limita el cuerpo a 2.900.000 bytes antes de JSON/auth/cuota;
PHP procesa multipart antes del controller y conserva su límite exterior
de post_max_size (20M observado). No se cambió configuración general del host.

```dart
AiActivationScreen({Key? key, AiActivation? activation,
                    http.Client Function()? clientFactory})
AiBudget({Key? key, required AiQuota? quota})
```

La pantalla lee, guarda, olvida y permite copiar el identificador del teléfono.
Se presenta sobre la pantalla llamadora, así volver conserva el borrador local;
el caller puede releer la activación al regresar. El estado consulta la tarea
`status`, que no llama al proveedor ni consume cuota. `AiBudget` presenta la
última cuota sin hacer consultas.

## Tareas v2

- `status`: `input: {}`; entrega `{enabled, tasks}` y cuota, sin proveedor y sin
  consumir intento.
- `meal_text`: texto de hasta 2.000 puntos Unicode y hasta 200 opciones de
  catálogo. Devuelve hasta ocho alimentos; `food_id` debe pertenecer a las
  opciones enviadas. Cantidad desconocida es `null`; macros no se solicitan.
- `food_label`: recibe MIME y foto base64 dentro del límite existente de 2 MiB
  y 1.024 px. Los valores son los que aparecen en la base leída, no conversiones
  del modelo. Si solo se ve kJ, las kcal quedan `null` y se agrega una duda.
- `report_question` y `exercise_question`: pregunta de hasta 1.000 puntos
  Unicode, una o dos fuentes (48.000 bytes UTF-8 combinados) e historial de hasta
  cuatro pares (4.000 puntos Unicode). La respuesta admite hasta 1.500 puntos,
  sin dígitos fuera de citas exactas de la fuente indicada.

En todas las tareas, el servidor debe validar el esquema completo y las
referencias literales antes de devolver el envelope. Los textos, fotos, fuentes
e historial son datos no confiables, nunca instrucciones. El cliente no persiste
la respuesta ni altera datos locales por consultar.

## Activación y presupuesto

```dart
final routeResult = await Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => AiActivationScreen()),
);
// La ruta anterior conserva su estado; releer si necesita el dato actualizado.
final (hwid, license) = await AiActivation().read();
```

El identificador se puede copiar para asignar la licencia a la cuenta y al canal
correctos. La licencia permanece en el almacenamiento Keystore ya existente.
No registrar errores crudos, cuerpo remoto, licencia, HWID, informes o imágenes.
