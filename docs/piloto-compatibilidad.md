# Matriz para el spike Android/tienda

Matriz original de fuente/SDK:9-oct-2026, based2d3070. El slice016 (10oct,
basec04b2a9) actualiza sólo la política y recursos Android descritos debajo;
no cambia SDK, dependencias, firma ni workflow. No es un recibo nativo.

| Elemento | Fuente actual comprobada | Próximo gate |
|---|---|---|
| Flutter / Dart | SDK local: Flutter3.22.0 / Dart3.4.0; framework5dcb86f68f239346676ceb1ed1ea385bd215fba1. pubspec requiere Dart>=3.4 | Spike aislado de compatibilidad antes de adoptar otra versión |
| Java | Configuración Android Java17/desugaring; runtime local17.0.12+8-LTS-286 | Fijar mismo JDK del spike y registrar versión |
| Gradle / AGP / Kotlin | wrapper8.7; AGP8.3.2; Kotlin1.9.22 | Compatibilidad de conjunto, build y ejecución; no actualizar un entero aislado |
| Android | min26; compile/target heredados del SDK fijado=34; package com.juandiego.seguimiento | APK exacto debe confirmar metadata. Target36 de tienda requiere spike |
| Notificaciones | lock flutter_local_notifications17.2.4, recurso release y permisos nativos existentes | Permiso concedido/negado, aviso en APKrelease con recursos recortados |
| Foto / archivos / compartir | lock image_picker1.1.2, file_picker8.3.2, share_plus10.1.4 | Cámara/galería/cancelación/EXIF, ZIP y destino, permisos Android recientes |
| Health Connect | Puente Kotlin propio; min26, permisos lectura/pasos y rationale en Manifest | Dispositivo soportado/no soportado, permiso negado/revocado, lote de pasos y retorno |
| Drift / SQLite | lock Drift2.21.0, schema20 en base; sqlite3 2.4.7 y libs nativas | Migraciones nuevas tras integración; columnas/filas/AI preservadas y restore |
| Gráficas / metadata | lock fl_chart0.69.2 / package_info_plus8.3.1 | Radar nuevo bajo SDK del spike y metadata APK nativa |
| Guion / wakelock | Sesión congelada local; lock wakelock_plus1.3.0 | Pausa→upgrade→reanudar→force-stop→reabrir, mismos índice/dosis |
| Firma / licencia | Misma identidad histórica, sin rotación. Activación Android Keystore en noBackupFilesDir | Apksigner, instalación -r y activación no incluida en ZIP/transferencia |
| Android backup | Candidata016: allowBackupfalse y reglas legacy/31+ excluyen cloud/D2D; ZIP/local conservados. [ADR0018](adr/0018-arranque-y-respaldo-android.md) | Verificar Manifest fusionado y transporte del APK exacto en QA. Configuración fuente no prueba teléfono/OEM ni elimina copias previas |
| Fuente→APK→upgrade | Herramientas 012 comparan artifacts/metadata | Recibo nuevo para candidato integrado; integración al pipeline pendiente |

La fuente oficial de Google Play consultada hoy exige target36(Android16) para
apps móviles nuevas y actualizaciones desde 31-ago-2026. Target34 no cumple ese
envío. La extensión posible hasta1-nov no está solicitada ni confirmada para
Seguimiento. [Requisito oficial](https://support.google.com/googleplay/android-developer/answer/11926878?hl=es).
La release personal por GitHub y la aceptación de tienda son gates distintos.

## Spike a ejecutar después de la integración

En otro worktree/SDK desechable, registrar commit+lock+JDK+Gradle+SDK, compilar una
vez y medir el APK resultante. Probar las filas nativas de la matriz, incluyendo
rechazos/ausencias y continuidad desde baseline pública con dataset ficticio.
Guardar recibos/logs/capturas; si falta acceso o falla un plugin, marcar BLOQUEADO
con causa concreta. No adoptar el SDK global ni cambiar firma para que pase.
Emitir ADR de compatibilidad sólo tras esa evidencia y decisión de adopción.

Comandos de descubrimiento usados: SDK fijado `flutter --version --machine`,
lectura de pubspec/lock, android/settings.gradle, wrapper, app/build.gradle y
FlutterExtension del SDK. Los APK anteriores son antecedentes, no una prueba
de runtime nuevo. No se diagnosticaron EOL, vulnerabilidades ni cumplimiento
legal a partir de la antigüedad del stack.
