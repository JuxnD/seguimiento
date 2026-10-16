# ADR 0018 — Actualizar desde la app: descarga, verificación e instalador

Fecha: 2026-10-16 · Estado: aceptada · Reemplaza en parte a
[ADR 0006](0006-actualizaciones-por-github-releases.md).

## Contexto

Con el ADR 0006, «Descargar APK» abría GitHub en el navegador. El 16 oct el
owner lo reportó como un paso raro: en otras apps, «Actualizar» hace todo el
proceso. El ADR 0006 había descartado instalar desde la app por el permiso
`REQUEST_INSTALL_PACKAGES` y la superficie de riesgo.

## Decisión

«Actualizar» (Ajustes → Actualizaciones):

1. Lee la release `latest` de GitHub, como antes.
2. Descarga el APK a `cache/updates` con progreso. Solo acepta `https` desde
   `github.com` o `*.githubusercontent.com`.
3. Lee el manifiesto publicado con el APK (`*.manifest.json`) y compara el
   SHA-256. Si no coincide, borra el archivo y no instala.
4. Abre el instalador del sistema mediante un `FileProvider` propio
   (`UpdateFileProvider`), que solo comparte esa carpeta.

Android sigue pidiendo confirmar cada instalación. La primera vez hay que
permitir «Instalar apps desconocidas» para My Prime; la app explica el paso
y abre ese ajuste. Android además rechaza un APK firmado con otra llave.

Si la release no trae manifiesto, o falla el canal nativo, queda «Descargar
con el navegador», como en el ADR 0006.

## Consecuencias

- **Permiso nuevo:** `REQUEST_INSTALL_PACKAGES`. La app solo instala lo que
  ella misma descargó y verificó contra el manifiesto de la release.
- **Publicación:** cada release debe llevar el `*.manifest.json` con `sha256`,
  como ya hace el canal de entrega desde la 1.24.
- **Sin cambios:** firmar con la misma llave sigue siendo el riesgo principal.
  Con otra llave, Android no actualiza.
