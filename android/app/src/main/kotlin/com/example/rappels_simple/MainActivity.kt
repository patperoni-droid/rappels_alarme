package com.example.rappels_simple

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {

    private val channelName = "rappels/alarm"
    private val tag = "MainActivity"

    // Compteur pour des requestCode garantis uniques
    companion object {
        private val rcSeq = AtomicInteger((System.currentTimeMillis() and 0x7fffffff).toInt())
        private fun nextRc(): Int {
            val v = rcSeq.incrementAndGet() and 0x7fffffff
            return if (v == 0) 1 else v
        }
    }

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
                        scheduleExactAlarmPro(this, whenMs, id, title, body)
                        result.success(null)
                    }
                    "cancel" -> {
                        val id = call.argument<Int>("id") ?: 0
                        Log.d(tag, "cancel() id=$id")
                        cancelAlarm(this, id)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // -------- Helpers "alarmes exactes" (Android 12+)
    private fun openExactAlarmSettings(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val i = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(i)
        }
    }

    private fun canUseExactAlarms(context: Context): Boolean {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.canScheduleExactAlarms()
        } else true
    }

    /**
     * Planification "PRO" côté Android :
     * - PendingIntent du Receiver 100% unique (action + data URI + requestCode)
     * - PendingIntent vers l’Activity aussi unique
     * - Vérifie l’autorisation "alarmes exactes" (Android 12+)
     * - setExactAndAllowWhileIdle() (ou setExact() < M) avec try/catch SecurityException
     */
    private fun scheduleExactAlarmPro(
        context: Context,
        whenMs: Long,
        id: Int,
        title: String,
        body: String
    ) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // URIs uniques pour éviter que le système considère deux PI "égaux"
        val uniqueFireUri = Uri.parse("alarm://${id}/${System.currentTimeMillis()}")
        val uniqueShowUri = Uri.parse("show://${id}/${System.currentTimeMillis()}")

        // ---- PI pour déclencher le Receiver
        val fireIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = "com.example.rappels_simple.ALARM_ACTION_$id"
            data = uniqueFireUri
            putExtra("id", id)
            putExtra("title", title)
            putExtra("body", body)
        }
        val fireRc = nextRc()
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val firePI = PendingIntent.getBroadcast(context, fireRc, fireIntent, flags)

        // ---- PI pour ouvrir l’app (facultatif, utile si on veut afficher l’écran)
        val showIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.example.rappels_simple.SHOW_$id"
            data = uniqueShowUri
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val showRc = nextRc()
        val showPI = PendingIntent.getActivity(context, showRc, showIntent, flags)

        Log.d(
            tag,
            "scheduleExactAlarmPro(): whenMs=$whenMs id=$id fireRc=$fireRc showRc=$showRc " +
                    "fireData=$uniqueFireUri showData=$uniqueShowUri"
        )

        // --- Vérif autorisation "alarmes exactes" sur Android 12+
        if (!canUseExactAlarms(context)) {
            Log.w(tag, "Exact alarms not allowed -> opening settings")
            openExactAlarmSettings(context)
            return
        }

        // --- Pose de l’alarme exacte
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMs, firePI)
                Log.d(tag, "setExactAndAllowWhileIdle posé (whenMs=$whenMs, rc=$fireRc)")
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, whenMs, firePI)
                Log.d(tag, "setExact posé (whenMs=$whenMs, rc=$fireRc)")
            }
        } catch (se: SecurityException) {
            // Si l’OS refuse encore -> écran système
            Log.e(tag, "SecurityException lors de setExact*: ${se.message}")
            openExactAlarmSettings(context)
        } catch (e: Exception) {
            Log.e(tag, "Erreur planification: ${e.message}", e)
        }
    }

    private fun cancelAlarm(context: Context, id: Int) {
        // Avec nos PI uniques (URI + requestCode distincts), il faudrait mémoriser
        // les requestCode/URI pour annuler précisément. On ne l’utilise pas ici.
        Log.d(tag, "cancelAlarm(): avec PI uniques, rien à annuler sans stocker les RC/URI.")
    }
}