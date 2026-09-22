# ADR 0006 — Actualizaciones por GitHub Releases, instaladas a mano

Fecha: 2026-09-22 · Estado: aceptada

## Contexto

La app es de uso personal y se instala como APK, fuera de Play Store. Hace
falta una forma de enterarse de que hay una versión nueva y de instalarla sin
perder los datos, sin montar un servidor ni publicar en una tienda.

## Decisión

Las versiones se publican como **GitHub Releases públicas** con el APK
adjunto. La app consulta `releases/latest`, compara la etiqueta (`vX.Y.Z`) con
su propia versión y ofrece abrir la descarga en el navegador. La instalación la
hace el usuario.

Todas las releases se firman con **la misma llave**, guardada como secret del
repositorio; `android/key.properties` y los `.jks` están fuera del control de
versiones.

## Alternativas

- **Play Store**: cuota, revisión y política de tiendas para una app de una sola
  persona. Desproporcionado.
- **Descarga e instalación automáticas dentro de la app**: exige el permiso
  `REQUEST_INSTALL_PACKAGES` y convierte a la app en instalador de binarios.
  Más superficie de riesgo que valor para este caso.
- **Servidor propio con un JSON de versiones**: hay que mantenerlo y pagarlo;
  GitHub ya da API, hosting del binario y notas de versión.

## Consecuencias

- Publicar = empujar una etiqueta; CI analiza, prueba, firma y publica.
- El repositorio debe ser público (o la app no puede leer la release sin token).
  El repositorio contiene código, no datos personales: la base de datos nunca
  sale del teléfono.
- Cambiar de llave rompe la actualización de las apps ya instaladas. Es el
  riesgo principal y está documentado en [actualizaciones.md](../actualizaciones.md).
- El chequeo depende de internet y falla en silencio: la app sigue siendo
  local-first y usable sin conexión.
- La comparación ante una etiqueta ilegible devuelve "no hay actualización":
  mejor no avisar que avisar mal.
