package com.juandiego.seguimiento

import androidx.core.content.FileProvider

/// Plan 058 (ADR 0018): comparte con el instalador del sistema sólo el APK
/// descargado en cache/updates. Subclase propia para no chocar con los
/// FileProvider de los plugins al unir los manifiestos.
class UpdateFileProvider : FileProvider()
