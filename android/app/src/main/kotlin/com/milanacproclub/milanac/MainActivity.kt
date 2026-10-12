package com.milanacproclub.milanac

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        // Con l'attività se ne va anche l'app Flutter, e con lei la chiamata.
        VoiceRoomService.stop(applicationContext)
        super.onDestroy()
    }
}
