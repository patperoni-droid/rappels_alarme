package com.example.rappels_simple

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "rappels/alarm"
    private val tag = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val whenMs = call.argument<Long>("whenMs") ?: 0L
                        val id = call.argument<Int>("id") ?: 0
                        val title = call.argument<String>("title") ?: "Rappel"
                        val body = call.argument<String>("body") ?: "C’est l’heure !"

                        Log.d(tag, "schedule() whenMs=$whenMs id=$id title=$title")
                        scheduleExactAlarmStable(this, whenMs, id, title, body)
                        result.success(null)
                    }
                    "cancel" -> {
                        val id = call.argument<Int>("id") ?: 0
                        Log.d(tag, "cancel() id=$id")
                        cancelAlarmStable(this, id)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Version STABLE : PendingIntent(APPEL RECEIVER) basé sur l'id :
     *  - requestCode = id
     *  - data = "alarm://$id"
     * Permet de recréer exactement le même PI pour annuler plus tard.
     */
    private fun stableFirePendingIntent(
        context: Context,
        id: Int,
        title: String? = null,
        body: String? = null
    ): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = "com.example.rappels_simple.ALARM_ACTION"
            data = Uri.parse("alarm://$id")
            putExtra("id", id)
            if (title != null) putExtra("title", title)
            if (body != null) putExtra("body", body)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_CANCEL_CURRENT
        }
        // requestCode = id -> stable
        return PendingIntent.getBroadcast(context, id, intent, flags)
    }

    private fun scheduleExactAlarmStable(
        context: Context,
        whenMs: Long,
        id: Int,
        title: String,
        body: String
    ) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // PI stable (on met le titre/corps pour la 1re création)
        val firePI = stableFirePendingIntent(context, id, title, body)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMs, firePI)
            Log.d(tag, "setExactAndAllowWhileIdle() posé (stable id=$id whenMs=$whenMs)")
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, whenMs, firePI)
            Log.d(tag, "setExact() posé (stable id=$id whenMs=$whenMs)")
        }
    }

    private fun cancelAlarmStable(context: Context, id: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // On recrée EXACTEMENT le même PI (même action, data, requestCode=id)
        val firePI = stableFirePendingIntent(context, id)
        am.cancel(firePI)
        firePI.cancel()
        Log.d(tag, "cancelAlarmStable(): annulé id=$id")
    }
}