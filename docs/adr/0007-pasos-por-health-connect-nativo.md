# ADR 0007 — Pasos del reloj por Health Connect, con código nativo propio

Fecha: 2026-09-28 · Estado: aceptada

## Contexto

El reloj SW/46 tiene firmware cerrado y solo habla con su app (Innova
S-Watch). Esa app ofrece *Yo → Health Connect → Conectar* y escribe los pasos
ahí. El usuario lo conectó el 28 sep 2026. La app necesita esos pasos para la
meta diaria sin que el usuario los copie a mano.

El proyecto está fijado en Flutter 3.22 (ADR 0001, README): los plugins de
salud actuales (`health` y otros) arrastran dependencias que piden Dart ≥ 3.5
o compileSdk 35, y `pub` puede resolverlos aunque luego no compilen.

## Decisión

- Leer solo **pasos** (`READ_STEPS`) con la librería oficial
  `androidx.health.connect:connect-client` **1.1.0-alpha07** (la última que
  compila con compileSdk 34), desde `HealthConnectBridge.kt` por el canal
  `seguimiento/salud`. Nada se escribe en Health Connect.
- `minSdk` sube de 21 a **26**, lo que exige la librería.
- En Android 14+ el permiso se pide con `requestPermissions` (Health Connect es
  del sistema); en Android 13 o anterior, con el contrato de la librería. El
  contrato solo funciona desde un `ComponentActivity` y `FlutterActivity` no lo
  es: por eso la bifurcación.
- La sincronización es opt-in (*Ajustes → Pasos del reloj → Conectar*), corre
  al abrir la app, al volver de segundo plano, **cada 2 min mientras la app
  está abierta** y al deslizar Hoy hacia abajo (desde la 1.10.0); trae 14 días y escribe en
  `daily_steps` con `source = health_connect`. Regla de fusión en
  `mergeSyncedSteps`: día vacío toma lo sincronizado; día que ya venía de
  Health Connect se actualiza; día anotado a mano solo cambia si lo
  sincronizado es mayor.

## Consecuencias

- No hay sincronización en segundo plano: si la app no se abre, los pasos
  llegan la próxima vez que se abra (el informe los tendrá igual). Leer en
  segundo plano exige el permiso `READ_HEALTH_DATA_IN_BACKGROUND` y un
  trabajo de Android propio; queda pendiente.
- Los pasos solo llegan cuando la app del reloj (Innova) sincroniza con
  Health Connect: si Innova no escribió, no hay nada nuevo que traer. Hoy
  muestra quién escribió el último registro y a qué hora (ver la adenda).
- Health Connect deduplica entre fuentes con la prioridad que el usuario fije
  en él; si el teléfono también cuenta pasos, la cifra es la que Health
  Connect considera buena, no la suma.
- Actualizar Flutter permitiría cambiar a una versión estable de
  `connect-client`; revisar al subir compileSdk a 35.

## Adenda del 5 oct 2026 (§16.14): la fuente real

Hecho observado: Innova (`com.moyoung.innov`) escribe **por lotes al
sincronizar**, con la hora de la sincronización: una caminata de 2.028 pasos
llegó como un solo registro de 3:05 a 3:06 p. m. Por eso:

- El total del día sigue siendo el **agregado** `COUNT_TOTAL` por día local
  (`aggregateGroupByPeriod`), no la suma de registros: respeta la prioridad
  de fuentes y no cuenta dos veces teléfono y reloj. Nada filtra registros
  cortos: el lote de un minuto cuenta completo.
- `lastStepsSync` (Kotlin) devuelve el registro más reciente de los últimos
  3 días: hora de fin, paquete y nombre visible (con `<queries>` para Innova;
  si Android no lo deja ver, Dart usa "INNOVA S-WATCH" o el paquete). Cada
  sincronización lo guarda en `flags.json` (`lastStepsOrigin`).
- Hoy (`lib/features/home/steps_source_line.dart`) muestra "INNOVA S-WATCH ·
  3:06 p. m." y, si ese registro tiene más de 6 h, "Abre la app del reloj
  para sincronizar". La hora en que esta app leyó dejó de mostrarse: lee cada
  2 min y no dice si los pasos están al día.
- Al volver a la app se sincroniza **sin limitar**: quien abre Innova para
  sincronizar y vuelve en un minuto debe ver los pasos ya; `coalesce` evita
  corridas simultáneas y el temporizador de 2 min sigue igual.
- Ajustes sugiere poner INNOVA S-WATCH de primera en *Health Connect → Datos
  y acceso → Actividad → Pasos → Prioridad de apps* cuando escribe más de una
  app.
- Límite: si el teléfono también escribe pasos, el "último registro" puede ser
  suyo y entonces el aviso de 6 h no salta aunque el reloj no haya
  sincronizado; la línea muestra el nombre de esa app, así que se nota.
