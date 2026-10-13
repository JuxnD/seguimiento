# Marca My Prime (036 vigente)

Nombre y MP/M-rayo final aprobados por owner. `seguimiento_icon.svg` es el
maestro único del icono, con nombre interno conservado; carbón171A1B,
limaC1FF45 y marfilF8F7F0. UIgeneral conserva su tema cálido.
`my_prime_wordmark.svg` es el maestro editable de letras geométricas: sin
fuente externa ni licencia tipográfica. Lema fuera del icono: «Construye tu
mejor versión». Variantes inversa/una tinta se derivan del maestro.

Ejecutar `python tool/icons.py`, `python tool/brand_assets.py`,
`python tool/icon_vector_test.py` y `python tool/android_policy_test.py`.
La hoja vigente está en `build/mockups/my-prime/proof-sheet.png`; no es captura
de Android. `icon_preview.py` corresponde a la exploración histórica013.

Renderer existente extendido a rellenoRGB explícito cerrado, un contorno
M/L/C/Z; conserva trazo redondo legado con píxeles exactos. Estilos,
transforms, múltiples subpaths, comandos desconocidos y fill/stroke ambiguo
fallan. No PNGretocado manualmente ni segundo renderer.

`icon_verify` regenera5fuentes+25PNGAndroid desde el maestro en directorio
temporal y compara píxeles entregados, además de alpha/safezone/nombres.
Una S antigua bien formada no puede pasar como MP. `android_policy_verify`
conserva un pin independiente de30PNG revisados en036-evidence; no sobrescribir
ese pin durante chequeos habituales. Cambio futuro exige decisión/revisión.

Cambian etiquetas visibles. PackageId, claseSeguimientoApp, SQLite, rutas,
firma y nombres de recursos siguen iguales. GatesFlutter/integración/nativo/
APK/teléfono separados. La selección humana ya está satisfecha.

## Historia013 (supersedida, conservar procedencia)

Fuente editable única: `seguimiento_icon.svg`. Candidata013: **S en movimiento**,
una ruta continua con la inicial de Seguimiento. Negro cálido `#0B0806` y naranja
`#F08A34` de la app. Sin tipografía incrustada, foto, peso, atleta anatómico,
calificación o promesa fija de diez rondas. Nombre/paquete/firma no cambian.

```powershell
python tool/icons.py
python tool/icon_verify.py --receipt build/mockups/logo/resource-receipt.json
python tool/icon_preview.py --out build/mockups/logo
```

Pillow ya era la dependencia del pipeline; no se añadió motor SVG externo.
`tool/icon_vector.py` interpreta el subconjunto geométrico explícito del SVG
(rectángulo, círculo y trazo absoluto M/L/C/Z con extremos/uniones redondos),
con supersampling4x y curvas Bézier muestreadas. Construye trazos por unión de
cápsulas, evitando huecos de las uniones densas de ImageDraw.line. Atributos o
transformaciones no soportados fallan; ampliar el renderer antes de usar otra
geometría, nunca editar PNG a mano para separarlo de la fuente.

Grilla editable1024 equivalente al canvas adaptable108dp. Foreground432
transparente respeta el círculo seguro72dp. Legacy/store usan la misma
geometría con encuadre óptico800x800 central, ampliado a1024/512. La capa
monocroma se renderiza desde el mismo trazo en blanco, sin filtro de luminosidad.
La barra de estado recorta el círculo seguro y conserva exclusivamente alpha;
no hay cuadrado opaco ni segmentos apagados.

Generación produce cinco fuentes PNG y25PNG Android en cinco densidades:
launcher clásico48dp, foreground/background/monochrome108dp y status24dp.
El XML adaptable apunta a la capa monocroma propia. Los nombres consumidos por
Manifest y NotificationService permanecen idénticos. No cambiar nombre app ni
applicationId/firma para probar una marca.

Preview genera20tamaños (16–512px)×4máscaras circular/squircle/redondeada/mono,
comparación con el icono anterior y otra dirección (atleta/arco) y vista móvil.
El baseline anterior se lee de Git d2d3070; para una renovación futura indicar
`--baseline-ref <commit>` al generador de preview. Si ese histórico no existe
en el checkout, la comparación falla explícitamente; no afecta tool/icons.py.
Marca “propuesta, no instalada”. La alternativa es sólo comparación; no se
genera como recurso Android. `icon_verify.py` valida archivos reales, tamaños,
transparencia, blanco de status/mono, círculo seguro y referencias XML, y deja
hashes. Su veredicto prueba entradas de recursos, no la aceptación visual ni
el APK final. En la candidata integrada falta comprobar launcher, íconos
temáticos y notificación release con R8 y permisos reales.
