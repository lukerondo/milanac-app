import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';

/// Avviso fisso "Sei nella stanza vocale di #canale" finché si è dentro, e i
/// permessi Android della stanza.
///
/// Su Android è un servizio in primo piano di tipo microfono (VoiceRoomService in
/// MainActivity.kt): senza, con l'app in background o lo schermo spento il
/// microfono registra solo silenzio. Su iOS basta la modalità "audio" in background
/// (Info.plist); sul web, nella demo e nei test non fa niente.
abstract class VoiceForeground {
  /// Avvia (o aggiorna) l'avviso; false se adesso il telefono non lo permette
  /// (per esempio app già in background): si riprova al ritorno nell'app.
  Future<bool> start(String channelName);

  Future<void> stop();

  /// L'avviso è davvero attivo. Android può rifiutarlo anche dopo aver accettato
  /// l'avvio (dentro il servizio: su Android 14 se l'app è appena andata in
  /// background), o fermarlo dopo: al ritorno nell'app si controlla e si riavvia.
  Future<bool> isRunning();

  /// Android 12+: con gli auricolari Bluetooth collegati, la stanza li usa solo con
  /// il permesso "Dispositivi nelle vicinanze". Se manca lo chiede (una volta) e
  /// aspetta la risposta, così la chiamata parte già con gli auricolari.
  Future<void> askBluetooth();
}

final voiceForegroundProvider = Provider<VoiceForeground>(
  (ref) =>
      !kIsWeb &&
          !AppConfig.isDemo &&
          defaultTargetPlatform == TargetPlatform.android
      ? const AndroidVoiceForeground()
      : const NoVoiceForeground(),
);

class AndroidVoiceForeground implements VoiceForeground {
  const AndroidVoiceForeground();

  static const _channel = MethodChannel('milanac/stanza_vocale');

  @override
  Future<bool> start(String channelName) async {
    try {
      return await _channel.invokeMethod<bool>('start', {
            'title': 'Sei nella stanza vocale di #$channelName',
            'text': 'Tocca per tornare nell\'app',
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  @override
  Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('running') ?? false;
    } catch (_) {
      // Non si sa: si riavvia (ripartire quando è già attivo non fa danni).
      return false;
    }
  }

  @override
  Future<void> askBluetooth() async {
    try {
      // true se è partito il dialogo del sistema.
      if (await _channel.invokeMethod<bool>('bluetooth') ?? false) {
        await waitForSystemDialog();
      }
    } catch (_) {}
  }
}

class NoVoiceForeground implements VoiceForeground {
  const NoVoiceForeground();

  @override
  Future<bool> start(String channelName) async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<bool> isRunning() async => true;

  @override
  Future<void> askBluetooth() async {}
}

/// Dopo una richiesta di permesso: il dialogo del sistema mette l'app in pausa e la
/// risposta arriva quando torna in primo piano. Se entro [appear] l'app non va in
/// pausa (nessun dialogo: il permesso era già stato negato per sempre) non si
/// aspetta; una risposta che non arriva entro [answer] non blocca la stanza.
Future<void> waitForSystemDialog({
  Duration appear = const Duration(milliseconds: 800),
  Duration answer = const Duration(minutes: 1),
}) async {
  final watcher = _DialogWatcher();
  final binding = WidgetsBinding.instance;
  final now = binding.lifecycleState;
  if (now != null && now != AppLifecycleState.resumed) {
    watcher.away.complete();
  }
  binding.addObserver(watcher);
  try {
    await watcher.away.future.timeout(appear);
    await watcher.back.future.timeout(answer);
  } on TimeoutException {
    // Nessun dialogo, o nessuna risposta: si va avanti.
  } finally {
    binding.removeObserver(watcher);
  }
}

class _DialogWatcher with WidgetsBindingObserver {
  final away = Completer<void>();
  final back = Completer<void>();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      if (!away.isCompleted) away.complete();
    } else if (away.isCompleted && !back.isCompleted) {
      back.complete();
    }
  }
}
