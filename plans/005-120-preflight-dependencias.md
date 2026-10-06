# Plan 005: preservar el orden de dependencias al desplegar

P1, corrección de la herramienta de entrega, requisito de Plan 004.
Autoridad: publicación y despliegue de la nueva versión autorizados por el owner.
Ejecutor: execute_gateway_120, worktree aislado Control360i 120-gateway.

## Evidencia

El preflight sobre 05a25d5 valida los cuatro archivos, pero ordena AiService y
Assistant antes de Transport. Reconoce `APP . '/services/...'`, pero omite los
`require_once __DIR__ . '/...'`. Además, elevar la profundidad de un padre ya
procesado no propaga la prioridad a sus dependencias. Publicar ese batch podría
interrumpir temporalmente las consultas de 1.19. Ningún archivo se ha subido.

## Corrección y scope

`scripts/deploy-preflight.ps1` y una prueba sintética de ese script; documentación
de deploy. Resolver includes literales relativos al archivo dentro del repositorio,
conservar la validación del objeto Git, sintaxis, modelos, staging vacío y árbol
limpio. Ordenar el grafo completo con detección de ciclos. No cambiar runtime,
credenciales ni rutas ERP. Sólo los cuatro archivos IA van a producción.

## Aceptación

Rojo contra 05a25d5 y verde: con sólo Controller y con los cuatro archivos en
orden adversarial, el staging contiene exactamente Transport, AiService,
Assistant y Controller, en ese orden. Dependencias ausentes o fuera del repo y
ciclos fallan; las referencias APP/INCLUDES ya soportadas conservan su protección.
Commit limpio, diff revisado y preflight repetido por root antes de SFTP.

Estado: COMPLETE técnico. Rojo/verde con seis casos y 24 guardas de deploy;
root repitió preflight, orden y relectura antes/después de los despliegues.
Con InputReader son cinco runtimes, sin modificar ERP ni subir secretos.
