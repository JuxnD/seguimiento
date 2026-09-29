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
  muestra "Pasos del reloj · actualizado HH:mm" para distinguirlo.
- Health Connect deduplica entre fuentes con la prioridad que el usuario fije
  en él; si el teléfono también cuenta pasos, la cifra es la que Health
  Connect considera buena, no la suma.
- Actualizar Flutter permitiría cambiar a una versión estable de
  `connect-client`; revisar al subir compileSdk a 35.
