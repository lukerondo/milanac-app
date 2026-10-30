package com.milanacproclub.milanac

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createClubNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Stanza vocale: avviso fisso e microfono attivo anche con l'app in background.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "milanac/stanza_vocale")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> result.success(
                        VoiceRoomService.start(
                            applicationContext,
                            call.argument<String>("title") ?: "Sei nella stanza vocale",
                            call.argument<String>("text") ?: "",
                        ),
                    )
                    "stop" -> {
                        VoiceRoomService.stop(applicationContext)
                        result.success(null)
                    }
                    // Al ritorno nell'app: l'avviso è davvero partito? (se no, si riavvia)
                    "running" -> result.success(VoiceRoomService.isRunning())
                    // Auricolari Bluetooth: true se è partito il dialogo del permesso.
                    "bluetooth" -> result.success(VoiceRoomService.askBluetooth(this@MainActivity))
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        // Con l'attività se ne va anche l'app Flutter, e con lei la chiamata.
        VoiceRoomService.stop(applicationContext)
        super.onDestroy()
    }

    /**
     * Canale "Avvisi del club" (Android 8+) per le notifiche push: Firebase lo usa per
     * quelle che non ne indicano uno (default_notification_channel_id nel manifest).
     * Crearlo di nuovo a ogni avvio non cambia niente, e le scelte fatte dall'utente
     * nelle impostazioni del telefono restano.
     */
    private fun createClubNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.canale_avvisi_club),
            "Avvisi del club",
            NotificationManager.IMPORTANCE_HIGH,
        )
        channel.description =
            "Chat, formazione, presenze, regolamento e avvisi del Direttivo"
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }
}
