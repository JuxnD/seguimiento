package com.juandiego.seguimiento

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate
import java.time.Period
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/// Pasos desde Health Connect, solo lectura. La app del reloj (Innova
/// S-Watch) escribe ahí los pasos del SW/46; esta app los lee por día.
/// Canal "seguimiento/salud"; el lado Dart está en lib/data/health_connect.dart.
class HealthConnectBridge(private val activity: Activity) {
    companion object {
        const val REQUEST_PERMISSIONS = 4711
        private const val PROVIDER = "com.google.android.apps.healthdata"
    }

    private val scope = MainScope()
    private val permissions = setOf(HealthPermission.getReadPermission(StepsRecord::class))
    private val contract = PermissionController.createRequestPermissionResultContract()
    private var pending: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "hasPermission" -> launch(result) { granted() }
            "requestPermission" -> requestPermission(result)
            "stepsByDay" -> launch(result) { stepsByDay(day(call, "from"), day(call, "to")) }
            "sources" -> launch(result) { sources(day(call, "from"), day(call, "to")) }
            "openSettings" -> result.success(openSettings())
            "installProvider" -> result.success(installProvider())
            else -> result.notImplemented()
        }
    }

    /// "disponible", "actualizar" (hay que actualizar Health Connect),
    /// "no_instalado" (Android 13 o anterior sin la app) o "no_soportado".
    private fun status(): String = when (HealthConnectClient.getSdkStatus(activity, PROVIDER)) {
        HealthConnectClient.SDK_AVAILABLE -> "disponible"
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "actualizar"
        else -> if (android.os.Build.VERSION.SDK_INT >= 34) "no_soportado" else "no_instalado"
    }

    private fun client() = HealthConnectClient.getOrCreate(activity)

    private suspend fun granted(): Boolean =
        client().permissionController.getGrantedPermissions().containsAll(permissions)

    private fun requestPermission(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("ocupado", "Ya hay una solicitud de permiso abierta", null)
            return
        }
        pending = result
        // En Android 14+ Health Connect es del sistema y sus permisos se piden
        // como cualquier permiso de ejecución. El contrato de la librería
        // depende de un ComponentActivity que intercepte su intent, y
        // FlutterActivity no lo es: por eso aquí se pide directo.
        if (android.os.Build.VERSION.SDK_INT >= 34) {
            activity.requestPermissions(permissions.toTypedArray(), REQUEST_PERMISSIONS)
            return
        }
        try {
            activity.startActivityForResult(contract.createIntent(activity, permissions), REQUEST_PERMISSIONS)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.success(false)
        }
    }

    /// Android 13 o anterior: lo llama MainActivity. true si era de esta solicitud.
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PERMISSIONS) return false
        val granted = contract.parseResult(resultCode, data)
        pending?.success(granted.containsAll(permissions))
        pending = null
        return true
    }

    /// Android 14+: lo llama MainActivity. Se vuelve a consultar a Health
    /// Connect en vez de confiar en el arreglo de resultados.
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_PERMISSIONS) return false
        val result = pending ?: return true
        pending = null
        scope.launch {
            try {
                result.success(granted())
            } catch (e: Exception) {
                result.success(false)
            }
        }
        return true
    }

    /// Pasos por día local ("YYYY-MM-DD" → pasos). Health Connect ya
    /// descarta los duplicados entre fuentes según la prioridad del usuario.
    private suspend fun stepsByDay(from: LocalDate, to: LocalDate): Map<String, Int> {
        val request = AggregateGroupByPeriodRequest(
            metrics = setOf(StepsRecord.COUNT_TOTAL),
            timeRangeFilter = TimeRangeFilter.between(from.atStartOfDay(), to.plusDays(1).atStartOfDay()),
            timeRangeSlicer = Period.ofDays(1),
        )
        return client().aggregateGroupByPeriod(request).associate {
            it.startTime.toLocalDate().toString() to (it.result[StepsRecord.COUNT_TOTAL] ?: 0L).toInt()
        }
    }

    /// Apps que escribieron pasos en el rango, por nombre visible: sirve para
    /// comprobar que llegan del reloj y no solo del teléfono.
    private suspend fun sources(from: LocalDate, to: LocalDate): List<String> {
        val request = ReadRecordsRequest(
            recordType = StepsRecord::class,
            timeRangeFilter = TimeRangeFilter.between(from.atStartOfDay(), to.plusDays(1).atStartOfDay()),
        )
        return client().readRecords(request).records
            .map { it.metadata.dataOrigin.packageName }
            .distinct()
            .map { label(it) }
    }

    private fun label(pkg: String): String = try {
        val pm = activity.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: PackageManager.NameNotFoundException) {
        pkg
    }

    private fun openSettings(): Boolean = open(Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS")) ||
        open(Intent("android.health.connect.action.HEALTH_HOME_SETTINGS"))

    private fun installProvider(): Boolean =
        open(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$PROVIDER"))) ||
            open(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$PROVIDER")))

    private fun open(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    }

    private fun day(call: MethodCall, key: String): LocalDate = LocalDate.parse(call.argument<String>(key)!!)

    private fun <T> launch(result: MethodChannel.Result, block: suspend () -> T) {
        scope.launch {
            try {
                result.success(block())
            } catch (e: SecurityException) {
                // Sin permiso: Dart lo trata como "hay que conectar".
                result.error("sin_permiso", e.message, null)
            } catch (e: Exception) {
                result.error("health_connect", e.message, null)
            }
        }
    }

    fun dispose() = scope.cancel()
}
