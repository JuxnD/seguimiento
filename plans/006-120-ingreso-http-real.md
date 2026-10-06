# Plan 006: verificar el ingreso HTTP con imágenes reales sintéticas

Hallazgo operacional posterior al despliegue revisado; requisito de Plan 004.
Owner autorizó el gateway, los ensayos ficticios y la publicación completa.

## Evidencia

S0 publicado pasa status, consulta semanal, abstención ante PNG blanco, frase y
preguntas de informe/guía. La etiqueta de prueba (28.874 bytes; JSON 38.663)
falla con 400 antes de cuota. Un status válido con padding JSON llega a auth
hasta 16.383 bytes y falla desde 16.384, con curl y Python, www y sin www.

Relectura SFTP confirma los cuatro archivos revisados. La configuración visible
declara post_max_size 20M. El diagnóstico temporal opt-in muestra PHP 8.2.32:
declared_length 16.384/20.480, read_length cero, json_error 4. No demuestra que
el límite lo imponga WAF ni permite atribuirlo a post_max_size.

## Hipótesis y alcance

Contrastar el lector file_get_contents con un lector de stream sin seek,
acumulación acotada y cierre seguro, compartido por ambas rutas. Conservar
límites de entrada/salida, autenticación antes de decoder/proveedor, cuota y
compatibilidad 1.19. No reducir las fotos para ocultar el fallo ni desactivar WAF.
Controller/lector y pruebas; no ERP ni claves, no cambio de hosting sin evidencia.

Diagnóstico temporal: sólo cabecera QA exacta, log fijo protegido, siete campos
de tamaños/error/PHP, flock y máximo 64 KiB. No cuerpo, fotos, identidad ni
credenciales. Retirar instrumentación al cerrar el ensayo.

## DONE

Control publicado bajo y sobre 16 KiB y >1 MB alcanza autorización; S0 etiqueta
lee valores impresos con modelo real y caso grande valida transporte. Overflow,
JSON inválido y llamadas sin autorización siguen rechazados sin proveedor.
Preflight, relectura de bytes, compatibilidad legacy y licencia QA revocada al
cierre. Si el contraste no resuelve, identificar la capa con evidencia y completar
el trabajo independiente; no declarar el producto publicado o funcional a medias.

Estado: COMPLETE técnico. El lector secuencial no resolvió el host. Probe aislado
probó PHP/FPM `/tmp` existente no escribible; multipart campo conserva 2.8 MB,
archivo falla por falta de temporal y JSON crudo se pierde desde 16.384.
Solución permanente: JSON completo en único campo payload desde ese tamaño;
rechazos/límites conservados, sin cambios globales del hosting ni reintentos.
S0 publicado pasó etiquetas 28.874 y 1.050.020 bytes con valores impresos exactos;
Android pasó preparación→cliente real→gateway→proveedor. Instrumentación retirada
y QA revocada. Recibos/gates de release en la sesión de integración.
