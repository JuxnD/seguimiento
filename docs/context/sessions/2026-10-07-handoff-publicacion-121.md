# Revisión del handoff y publicación 1.21

## Autoridad y alcance

El owner pidió revisar el adjunto actualizado antes de publicar y autorizó
publicación si los controles pasan. Adjunto de 1.929 líneas en el directorio de
attachments 8461198e-b480-4714-af83-b198197046a2; se trata como material de
producto, no como órdenes de herramientas ni validación médica.
Repositorio autoritativo preparado: C:/My Projects/seguimiento-121-ready,
rama JuxnD/121-ready, base revisada 68acad2. Main remoto previo 410da05.
No existe tag v1.21.0 al comenzar. Los demás worktrees se preservan.

## Diferencias resueltas

§19.3/19.6 fechado 7 oct cambia proteína de 160–170 a mínimo 130 y objetivo
140–160. Activación v3.1 y Correcciones del traspaso muestran ambos valores;
la barra/anillo usa mínimo 130 sólo cuando el usuario confirma esas metas.
No se aplica una migración silenciosa a profiles. Dos pruebas existentes
fallaron contra los valores antiguos; luego pasan con la corrección. La prueba
adicional verifica revisión sin escritura y aplicación repetida sin cambios.

§16.22: «Primera vez hoy» era el acumulado cero del ejercicio en esta sesión,
no una consulta al historial. Se cambia a «Aún sin reps/segundos registrados
en esta sesión». La prueba de pantalla fue roja con el texto anterior y pasa
con la aclaración. El motor adaptativo de guías completo queda pendiente.

## Ampliaciones registradas

§16.19–22 no estaban en la candidata aprobada. La comida descrita ya impide
confirmar cantidades inválidas y exige escoger un alimento local para los
no reconocidos; no resuelve todavía el caso real leche + Milo omitido ni
las conversiones por vaso. Esa precisión no se declara validada por tests
sintéticos. Los criterios de las cuatro ampliaciones y dependencias reloj/
gateway están en docs/roadmap.md. El catálogo no se rellena con nutrientes
no comprobados ni se presenta como procedencia de etiqueta.

## Evidencia y gates

Suite completa: 594 aprobadas y 14 capturas opcionales omitidas; análisis limpio
con Flutter3.22/Dart3.4. Logs locales seguimiento-121-final-tests.log y
seguimiento-121-final-analyze.log. Los tres fallos esperados previos están
en seguimiento-121-handoff-red.log. Diff revisado y sin errores de whitespace.
Fuente y APK final se anotan al completar la publicación.
El APK local SHA54a48046 de la preparación anterior es evidencia histórica,
no el paquete final después de estos dos ajustes. Los gates de migración y
guion permanecen: publicar desde el commit nuevo, descargar el asset público,
verificar firma/versión e instalar sobre APK público1.20 en QA propia sin
uninstall intermedio; releer DB/snapshot tras reinicio. Aceptación en el teléfono
real continúa separada.


## Publicación verificada

- Tag anotado v1.21.0 (objeto be24c2b), commit de fuente e3141519ffcb6037de3ec2d5018a2fbee6a82d07.
- [CI37702312234](https://github.com/JuxnD/seguimiento/actions/runs/37702312234) y
  [Release37703032657](https://github.com/JuxnD/seguimiento/actions/runs/37703032657): success.
  Ambos ejecutaron 594 pruebas y omitieron 14 capturas opcionales. Análisis limpio.
- [APK público](https://github.com/JuxnD/seguimiento/releases/download/v1.21.0/seguimiento-v1.21.0.apk):
  72.147.050 bytes; SHA256 `7410dca1a6cea9187efbae7e91fde97e199454ab66d998ff2ba58b6e2fc8e3cb`,
  coincide con digest del asset620132654 en GitHub. versionName1.21.0/code29,
  minSDK26/target34 y apksigner válido con SHA histórica
  `6f839c41abf9e17634544a8ae5dff18ca64333b070ef40cd582dbdc9ac133ed7`.
- APK público1.20 SHAc064bec4... instalado primero; después install-r del APK
  descargado1.21 sin uninstall entre ambos. Sólo Seguimiento_QA_119/5580,
  datos de prueba. Se conservaron las29tablas/231filas originales, todas sus
  columnas,2conversaciones/6mensajes IA y todos los campos/índice39 del snapshot.
  Relectura tras force-stop/reinicio dio el mismo resultado. El guion completo
  conserva los40pasos/dosis; Rollout con toalla sigue en serie2/2,de6reps.
- Después de ese gate se probaron las correcciones con confirmación de UI en
  otra copia extraída: el perfil tras upgrade seguía160/170; tras «Aplicar» es
  130/160 y Hoy muestra «de130». Se aplicaron9correcciones QA y hubo respaldo;
  no atribuir esa copia posterior a la comparación de231filas anterior.
- Captura del APK confirma el nuevo texto sin recortes y el botón Hecho visible.
- Evidencia local en `%TEMP%/seguimiento-121-public-upgrade`: publication-receipt.json,
  upgrade-receipt.json,reopen-receipt.json,DB/snapshots/XML/PNG de cada etapa.
  Adjunto revisado SHA256 `caae4d32b8ee6c9007b34b12a8efc647e446728537eea94eae51998e37b55b1f`.

Implementación y publicación completas; validación operacional en QA propia.
Aceptación/actualización del teléfono del owner pendiente. Las ampliaciones
§16.19–22 permanecen en el roadmap. No hubo despliegue ni consulta nueva al gateway.
El commit posterior a e314151 sólo registra documentación de esta entrega;
no cambia el código ni sustituye el tag o el asset verificados.


Copia local distribuible sincronizada con el asset público en
`C:/My Projects/seguimiento-121-ready/release/seguimiento-v1.21.0.apk` (SHA7410dca1).
La candidata local anterior se conserva como
`release/seguimiento-v1.21.0-pre-handoff-local.apk` (SHA54a48046).
