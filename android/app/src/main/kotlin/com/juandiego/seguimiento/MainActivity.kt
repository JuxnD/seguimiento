package com.juandiego.seguimiento

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Expone a Dart lo que Android no deja ver desde los plugins: si la app está
/// bajo optimización de batería y si "Pausar la actividad de la app si no se
/// usa" está activo. Ambos pueden callar los recordatorios programados.
class MainActivity : FlutterActivity() {
    private var health: HealthConnectBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ai = AiCredentialsBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "seguimiento/ia")
            .setMethodCallHandler { call, result -> ai.handle(call, result) }
        val bridge = HealthConnectBridge(this).also { health = it }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "seguimiento/salud")
            .setMethodCallHandler { call, result -> bridge.handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "seguimiento/sistema").setMethodCallHandler { call, result ->
            when (call.method) {
                "batteryOptimized" -> result.success(batteryOptimized())
                "pausedIfUnused" -> result.success(pausedIfUnused())
                "openBatterySettings" -> result.success(
                    open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) || openAppDetails()
                )
                "openUnusedAppSettings" -> result.success(openUnusedAppSettings())
                "openAppDetails" -> result.success(openAppDetails())
                "openApkDownload" -> openApkDownload(call.argument<String>("url"), result)
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("FlutterActivity todavía entrega los resultados por aquí")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (health?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (health?.onRequestPermissionsResult(requestCode) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        health?.dispose()
        super.onDestroy()
    }

    /// Abre la descarga del APK en su propia tarea y cierra la de la app
    /// (§16.13). Si el navegador y luego el instalador se quedaban dentro de la
    /// tarea de la app, al terminar "Abrir" creaba otra y en recientes quedaban
    /// dos "Seguimiento" (una en Ajustes, otra en Hoy). El proceso muere igual
    /// al instalar encima: no se pierde nada que no estuviera guardado ya.
    private fun openApkDownload(url: String?, result: MethodChannel.Result) {
        if (url == null) {
            result.success(false)
            return
        }
        val opened = open(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        result.success(opened)
        if (opened) finishAndRemoveTask()
    }

    /// true si Android puede diferir o recortar el trabajo de la app en reposo.
    private fun batteryOptimized(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return !pm.isIgnoringBatteryOptimizations(packageName)
    }

    /// true si está activo "Pausar la actividad de la app si no se usa"
    /// (Android 11+). null donde el ajuste no existe.
    private fun pausedIfUnused(): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return !packageManager.isAutoRevokeWhitelisted
    }

    private fun openUnusedAppSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(Intent.ACTION_AUTO_REVOKE_PERMISSIONS, Uri.fromParts("package", packageName, null))
            if (open(intent)) return true
        }
        return openAppDetails()
    }

    private fun openAppDetails(): Boolean =
        open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))

    /// Siempre en una tarea nueva: lo que se abre (ajustes, navegador) no debe
    /// quedar apilado dentro de la tarea de la app.
    private fun open(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    }
}
