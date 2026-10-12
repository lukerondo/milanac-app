import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Chi usa l'audio in primo piano.
enum AudioUse {
  /// Ascolto di un vocale in chat.
  vocale,

  /// Registrazione di un vocale in chat.
  registrazioneVocale,

  /// Riproduzione di un replay della lavagna.
  replay,

  /// Registrazione di un replay della lavagna.
  registrazioneReplay,

  /// Stanza vocale.
  chiamata,
}

/// Coordina le sorgenti audio dell'app:
/// - la musica di sottofondo resta in pausa finché qualcuno usa l'audio;
/// - chi inizia a suonare o registrare con [claim] ferma gli altri lettori
///   (ognuno ascolta [audioFocusProvider] e si ferma quando il suo uso sparisce);
/// - la stanza vocale non viene chiusa da un vocale: [claim] la lascia attiva
///   (chi registra può mettere in muto il microfono della stanza).
final audioFocusProvider = NotifierProvider<AudioFocus, Set<AudioUse>>(
  AudioFocus.new,
);

class AudioFocus extends Notifier<Set<AudioUse>> {
  @override
  Set<AudioUse> build() => const {};

  /// [use] prende l'audio: gli altri lettori e registratori lasciano il posto
  /// (tranne la stanza vocale, che resta).
  void claim(AudioUse use) {
    state = {
      use,
      if (use != AudioUse.chiamata && state.contains(AudioUse.chiamata))
        AudioUse.chiamata,
    };
  }

  /// [use] ha finito.
  void release(AudioUse use) {
    if (!state.contains(use)) return;
    state = {...state}..remove(use);
  }

  bool get busy => state.isNotEmpty;
}
