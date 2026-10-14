package com.juandiego.seguimiento

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import android.util.AtomicFile
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class RayitoWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        RayitoWidget.render(context, manager, ids)
    }
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in listOf(Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_BOOT_COMPLETED, "com.juandiego.seguimiento.RAYITO_DAY")) {
            val manager = AppWidgetManager.getInstance(context)
            RayitoWidget.render(context, manager, manager.getAppWidgetIds(ComponentName(context, RayitoWidgetProvider::class.java)))
        }
    }
}

object RayitoWidget {
    private fun snapshot(context: Context) = File(context.noBackupFilesDir, "rayito_widget.json")
    private fun image(context: Context) = File(context.noBackupFilesDir, "rayito_widget.png")
    private fun day() = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "clear") {
            AtomicFile(snapshot(context)).delete()
            image(context).delete()
            context.getSharedPreferences("rayito_widget", Context.MODE_PRIVATE).edit().clear().apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, RayitoWidgetProvider::class.java))
            render(context, manager, ids)
            result.success(ids.size)
            return
        }
        if (call.method != "update") { result.notImplemented(); return }
        try {
            val json = JSONObject()
            for (key in listOf("title", "streak", "today", "date", "semanticLabel")) json.put(key, call.argument<String>(key))
            val png = call.argument<ByteArray>("png") ?: throw IllegalArgumentException("missing image")
            json.put("png", Base64.encodeToString(png, Base64.NO_WRAP))
            val atomic = AtomicFile(snapshot(context))
            val output = atomic.startWrite()
            try {
                output.write(json.toString().toByteArray(Charsets.UTF_8))
                atomic.finishWrite(output)
            } catch (e: Exception) { atomic.failWrite(output); throw e }
            image(context).delete()
            // Remove the pre-integration cache if present; no portable data store.
            context.getSharedPreferences("rayito_widget", Context.MODE_PRIVATE).edit().clear().apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, RayitoWidgetProvider::class.java))
            render(context, manager, ids)
            result.success(ids.size)
        } catch (_: Exception) { result.error("widget_write", "No se pudo actualizar Rayito", null) }
    }

    fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
        if (ids.isEmpty()) return
        val json = try { JSONObject(AtomicFile(snapshot(context)).openRead().bufferedReader().use { it.readText() }) } catch (_: Exception) { JSONObject() }
        val fresh = json.optString("date") == day()
        val views = RemoteViews(context.packageName, R.layout.rayito_widget)
        if (fresh) {
            views.setTextViewText(R.id.rayito_widget_title, json.optString("title"))
            views.setTextViewText(R.id.rayito_widget_streak, json.optString("streak"))
            // The date remains visible even if Android delays the next update.
            views.setTextViewText(R.id.rayito_widget_today, day() + " · " + json.optString("today").removePrefix("Hoy: "))
            try { val bytes = Base64.decode(json.optString("png"), Base64.DEFAULT); BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { views.setImageViewBitmap(R.id.rayito_widget_image, it) } } catch (_: Exception) { }
            views.setContentDescription(R.id.rayito_widget_image, json.optString("semanticLabel"))
            views.setContentDescription(R.id.rayito_widget_root, json.optString("semanticLabel") + ", " + day())
        } else {
            views.setTextViewText(R.id.rayito_widget_title, "Rayito · My Prime")
            views.setTextViewText(R.id.rayito_widget_streak, "Abre Hoy para actualizar")
            views.setTextViewText(R.id.rayito_widget_today, day() + " · Toca para ver qué toca hoy")
            views.setContentDescription(R.id.rayito_widget_root, "My Prime. Abre Hoy para actualizar. " + day())
            views.setContentDescription(R.id.rayito_widget_image, "Rayito pendiente de actualizar")
            views.setImageViewResource(R.id.rayito_widget_image, R.mipmap.ic_launcher)
            AtomicFile(snapshot(context)).delete()
            image(context).delete()
        }
        val open = Intent(context, MainActivity::class.java).setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER).putExtra("rayito_open_today", true)
        val pending = PendingIntent.getActivity(context, 51, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.rayito_widget_root, pending)
        manager.updateAppWidget(ids, views)
        val midnight = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 1); set(Calendar.MILLISECOND, 0) }
        val refresh = PendingIntent.getBroadcast(context, 51, Intent(context, RayitoWidgetProvider::class.java)
            .setAction("com.juandiego.seguimiento.RAYITO_DAY"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).setAndAllowWhileIdle(AlarmManager.RTC, midnight.timeInMillis, refresh)
    }
}
