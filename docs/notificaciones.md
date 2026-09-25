# Notificaciones

Avisos locales, sin servidor ni cuenta. La app los programa en el teléfono y
los vuelve a calcular cada vez que cambia algo que los afecta.

## Qué avisa

| Aviso | Cuándo | Qué dice |
|---|---|---|
| Antes de la sesión | 15 min antes de la hora de entrenar (3:00 p. m. por defecto) | "En 15 min: Circuito" + el trabajo del día ("6 rondas: Dominadas 5 · Flexiones 10 · Sentadillas 15") |
| Sesión sin registrar | 9:00 p. m. de un día de entrenamiento sin sesión guardada | Recuerda registrarla, aunque no hayas entrenado |
| Comidas | Hora por franja: merienda 4:30 p. m. y cena 8:00 p. m. activas; desayuno apagado | Invita a usar un combo si repetiste |
| Proteína | 8:00 p. m., solo si vas por debajo del umbral (100 g) | "Proteína: 68 g — Faltan 62 g para el mínimo de 130 g" |
| Calorías | 8:00 p. m., solo si vas por debajo del umbral (1.800 kcal) | "Calorías: 1200 kcal — Faltan 1200 kcal para la meta de 2400" |
| Comidas sin registrar | 10:00 p. m., si falta desayuno, almuerzo o cena y el día no se cerró a mano | "Falta registrar: desayuno y cena" |
| Medición | La fecha acordada, o última toma + intervalo, a las 7:00 a. m. | En ayunas, antes de desayunar |
| Fin del descanso | Al terminar la cuenta regresiva de la sesión | Qué viene después; suena y vibra con la app en segundo plano |

Todo se activa, se apaga y se mueve de hora en **Ajustes → Recordatorios**.
Esa pantalla también muestra la cola de avisos ya programados, para comprobar
sin esperar a que suenen.

### ¿Llegan los avisos?

Arriba en Recordatorios, una tarjeta con lo que decide si un aviso llega:
permiso de notificaciones, alarmas exactas, **optimización de batería** y
**"Pausar la actividad de la app si no se usa"** (Android 11+). Los dos últimos
no los ve ningún plugin: los lee `MainActivity.kt` por el canal
`seguimiento/sistema` ([`system_health.dart`](../lib/data/system_health.dart)).
Si alguno está activo, un aviso explica el efecto y abre el ajuste exacto.

Dos pruebas separan las causas: **Probar ahora** (inmediato: si no aparece, es
el permiso o el canal) y **Probar en 1 min** (programado igual que los
recordatorios: si el inmediato llega y este no, es la alarma, la batería o el
fabricante). Verificado en el emulador Android 15 con la pantalla apagada.

## Cómo se decide

La regla de qué avisar vive en [`lib/domain/reminders.dart`](../lib/domain/reminders.dart),
sin dependencias de plataforma, y está cubierta por
[`test/domain/reminders_test.dart`](../test/domain/reminders_test.dart).
[`ReminderScheduler`](../lib/data/reminder_scheduler.dart) junta el plan, las
comidas del día y las medidas, y entrega la lista al sistema.

Reglas que importan:

- Si el día es de **fútbol o descanso**, no hay aviso de sesión.
- Si la sesión **ya está registrada**, los dos avisos de ese día se callan.
- El aviso de proteína se calcula con lo comido **hoy**; si ya pasaste el
  umbral, no se programa.
- Nada se programa en el pasado.
- Cada aviso tiene un id estable por tipo y día (`tipo·1000 + día del mes·24 +
  hora`): reprogramar no duplica. El horizonte es de 7 días, así que el día del
  mes no choca. El fin del descanso usa el id fijo `90001` y la cancelación
  masiva lo respeta.
- Los canales de Android se llaman `recordatorios` y `descanso`. **No se
  renombran**: el sistema crearía otro canal y el usuario perdería sus ajustes.

La reprogramación es completa (cancelar y volver a programar) y se dispara al
abrir la app, al cambiar el día (medianoche o al volver de segundo plano) y
cuando cambian sesiones, comidas de hoy, medidas, plan, perfil o los propios
ajustes. Pasa por una sola puerta (`rescheduleRemindersProvider`) que nunca
corre dos veces a la vez y no pierde cambios: si llega uno mientras corre, se
repite al terminar.

## Android

- `POST_NOTIFICATIONS` (13+) se pide **una sola vez**, en el primer arranque.
  Si se niega, la app funciona igual y Recordatorios ofrece pedirlo de nuevo.
- El fin del descanso usa **alarma exacta** (`SCHEDULE_EXACT_ALARM`): 30 s tarde
  no sirve. En Android 14+ ese permiso **no viene concedido**: la app lo
  comprueba, y si falta programa el aviso inexacto (puede llegar tarde), lo
  dice una vez en el cronómetro y Recordatorios muestra el botón para
  permitirlo. El resto de avisos usa alarmas inexactas, que gastan menos
  batería.
- Los receivers de `flutter_local_notifications` están declarados en
  [`AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml). **El
  plugin no los trae**: sin ellos la alarma se dispara y no aparece nada, sin
  ningún error visible. Hay una comprobación en CI que falla si se pierden.
- `RECEIVE_BOOT_COMPLETED` deja que los avisos sobrevivan a un reinicio.
- El ícono de la barra de estado es `@drawable/ic_stat_seguimiento` (blanco
  sobre transparente, generado por `tool/icons.py`): el del lanzador se veía
  como un cuadro gris.
- La app usa desugaring de `java.time` (`coreLibraryDesugaring`), que el plugin
  exige para `minSdk` 21.

## Límites conocidos

- El ahorro de batería agresivo de algunos fabricantes puede retrasar los avisos
  inexactos. La tarjeta de diagnóstico lo detecta y abre el ajuste; algunos
  fabricantes tienen además su propio gestor, que la app no puede leer.
- Los avisos se calculan con los datos del momento de programar: si registras
  una comida a las 7:55 p. m., los de proteína, calorías y comidas ya quedaron
  fijados con lo anterior salvo que la app esté abierta (ahí se reprograman
  solos al guardar, igual que al cerrar el día).
