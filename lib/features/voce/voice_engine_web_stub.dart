import 'voice_engine.dart';

/// Fuori dal browser il motore web non esiste (vedi `voice_engine_web.dart`).
VoiceEngine createWebVoiceEngine() =>
    throw UnsupportedError('La stanza vocale web esiste solo nel browser');
