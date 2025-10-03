package com.example.rappels_simple

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class AlarmReceiver : BroadcastReceiver() {

    private val tag = "AlarmReceiver"

    // Un canal distinct côté Android (on ne dépend pas du plugin Flutter ici)
    private val channelId = "rappels_sys"
    private val channelName = "Rappels (système)"
    private val channelDesc = "Notifications des rappels planifiés (canal Android)"

    override fun onReceive(context: Context, intent: Intent) {
        val id    = intent.getIntExtra("id", 0)
        val title = intent.getStringExtra("title") ?: "Rappel"
        val body  = intent.getStringExtra("body")  ?: "C’est l’heure !"

        Log.d(tag, "onReceive id=$id title=$title body=$body")

        ensureChannel(context)

        // Taper la notif : appui => rouvre l’app
        val openIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            action = "com.example.rappels_simple.OPEN_$id"
        }
        val openPI = PendingIntent.getActivity(
            context,
            id, // OK d'utiliser l'id en requestCode ici
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm) // remets ton icône si tu veux
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setContentIntent(openPI)
            .build()

        with(NotificationManagerCompat.from(context)) {
            notify(id, notif)
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val existing = nm.getNotificationChannel(channelId)
            if (existing == null) {
                val ch = NotificationChannel(
                    channelId, channelName, NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = channelDesc
                    enableVibration(true)
                    setShowBadge(false)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                }
                nm.createNotificationChannel(ch)
            }
        }
    }
}