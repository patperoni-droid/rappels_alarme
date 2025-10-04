package com.example.rappels_simple

import android.app.NotificationManager
import android.content.Context
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity

class AlarmActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_alarm)

        // Données reçues
        val id   = intent.getIntExtra("id", 0)
        val title = intent.getStringExtra("title") ?: getString(R.string.alarm_title_placeholder)
        val body  = intent.getStringExtra("body")  ?: getString(R.string.alarm_body_placeholder)

        // Remplir l’UI
        findViewById<TextView>(R.id.alarmTitle).text = title
        findViewById<TextView>(R.id.alarmBody).text  = body

        // Empêche le "back" tant que l’utilisateur n’a pas validé "J’ai vu"
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    // Ne rien faire : on bloque le back
                }
            }
        )

        // Bouton "J’ai vu" : annule la notif + ferme l’écran
        findViewById<Button>(R.id.dismissBtn).setOnClickListener {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(id)
            finish()
        }
    }
}