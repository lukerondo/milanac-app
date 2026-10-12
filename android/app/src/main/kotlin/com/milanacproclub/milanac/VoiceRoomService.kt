package com.milanacproclub.milanac

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Servizio in primo piano mentre si è nella stanza vocale, con la notifica fissa
 * "Sei nella stanza vocale di #canale". Da Android 9, senza un servizio così, con
 * l'app in background o lo schermo spento il microfono registra solo silenzio; da
 * Android 11 il servizio deve essere di tipo "microphone".
 *
 * Lo avvia e lo ferma l'app Flutter dal canale "milanac/stanza_vocale" (MainActivity),
 * che al ritorno nell'app chiede anche se è davvero attivo ([isRunning]): Android può
 * rifiutare l'avvio dentro onStartCommand, dopo averlo accettato.
 */
class VoiceRoomService : Service() {

    override fun onBind(intent: Intent): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Sei nella stanza vocale"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        // startForeground va chiamato sempre, anche se intanto è arrivato lo stop:
        // Android lo pretende entro pochi secondi da startForegroundService.
        try {
            val notification = buildNotification(title, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            running = true
        } catch (e: Exception) {
            // Android 14+: permesso del microfono mancante o app non più in primo piano.
            Log.w(TAG, "Avviso della stanza vocale non avviato", e)
            wanted = false
        }
        if (!wanted) stopSelf()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun buildNotification(title: String, text: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Stanza vocale",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.description = "Avviso fisso mentre sei in una stanza vocale"
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_notifica_club)
            .setContentTitle(title)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
        if (text.isNotEmpty()) builder.setContentText(text)
        // Toccando la notifica si torna nell'app (come dall'icona).
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    companion object {
        private const val TAG = "VoiceRoomService"
        private const val CHANNEL_ID = "stanza_vocale"
        private const val NOTIFICATION_ID = 4120
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val BLUETOOTH_REQUEST = 4121

        // Letti e scritti solo sul thread principale (canale Flutter e ciclo di vita
        // del servizio ci girano entrambi).
        /** L'app vuole il servizio attivo. */
        private var wanted = false

        /** startForeground riuscito e servizio non ancora distrutto. */
        private var running = false

        /** Il permesso Bluetooth è già stato chiesto mentre l'app è aperta. */
        private var bluetoothAsked = false

        /** L'avviso è davvero attivo (startForeground riuscito, servizio non distrutto). */
        fun isRunning(): Boolean = running

        /**
         * Android 12+: con auricolari Bluetooth collegati, Agora li usa solo con il
         * permesso "Dispositivi nelle vicinanze" (BLUETOOTH_CONNECT, dichiarato nel
         * manifest). Se manca lo chiede, una volta per apertura dell'app; true se è
         * partito il dialogo del sistema (la risposta arriva al ritorno nell'app).
         */
        fun askBluetooth(activity: Activity): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || bluetoothAsked) return false
            val permission = Manifest.permission.BLUETOOTH_CONNECT
            if (activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
                return false
            }
            // Senza auricolari Bluetooth il permesso non serve: niente dialogo.
            val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val bluetooth = audio.getDevices(AudioManager.GET_DEVICES_ALL).any {
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                    it.type == AudioDeviceInfo.TYPE_BLE_HEADSET
            }
            if (!bluetooth) return false
            bluetoothAsked = true
            activity.requestPermissions(arrayOf(permission), BLUETOOTH_REQUEST)
            return true
        }

        /** Avvia (o aggiorna) il servizio; false se adesso Android non lo permette. */
        fun start(context: Context, title: String, text: String): Boolean {
            val intent = Intent(context, VoiceRoomService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            wanted = true
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (e: Exception) {
                // Android 12+: con l'app in background non si può (si riprova al ritorno).
                Log.w(TAG, "Avviso della stanza vocale non avviato", e)
                wanted = false
                false
            }
        }

        fun stop(context: Context) {
            wanted = false
            // Se sta ancora partendo si ferma da sé, subito dopo startForeground:
            // fermarlo prima farebbe chiudere l'app ("did not then call startForeground").
            if (running) context.stopService(Intent(context, VoiceRoomService::class.java))
        }
    }
}
