# Fuentes para las pruebas de figuras

Copias sin modificar de los artefactos `material_fonts` de Flutter 3.22.0
(revisión `5dcb86f68f239346676ceb1ed1ea385bd215fba1`). Se usan solamente
en pruebas; no forman parte de los assets de la aplicación.

- Roboto regular, medium y bold: Google, licencia Apache 2.0 incluida en
  `roboto_license.txt`. Fuente: <https://github.com/googlefonts/roboto>.
- Material Icons: Google, licencia CC BY 4.0 incluida en
  `materialicons_license.txt` tal como viene en ese SDK. Fuente:
  <https://github.com/google/material-design-icons>.

`test/support/test_fonts.dart` carga Roboto, FlutterTest y MaterialIcons
desde estos archivos. Si falta una fuente, debe fallar la prueba; no hay
fallback ni dependencia de `FLUTTER_ROOT`. Al actualizar los fixtures,
conservar su procedencia, las licencias y revisar los renders de texto.
