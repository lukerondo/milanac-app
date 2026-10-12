import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chat/voice_player.dart';
import '../../features/voce/voice_call.dart';
import '../audio_focus.dart';
import '../auth/providers.dart';
import '../config.dart';
import 'push_service.dart';

/// Salva il token FCM del telefono (tabella device_tokens) per le notifiche personali.
class DeviceTokens {
  DeviceTokens(this._ref);
  final Ref _ref;

  Future<void> save(String token) async {
    if (AppConfig.isDemo) return;
    final client = _ref.read(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      // La funzione passa il token all'account attuale anche se il telefono
      // era registrato con un altro account (l'upsert diretto lo vieterebbe).
      await client.rpc(
        'register_device_token',
        params: {'p_token': token, 'p_platform': defaultTargetPlatform.name},
      );
    } on PostgrestException catch (e) {
      // Database non ancora aggiornato (funzione mancante): come prima.
      if (e.code != 'PGRST202') rethrow;
      await client.from('device_tokens').upsert({
        'token': token,
        'user_id': userId,
        'platform': defaultTargetPlatform.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  Future<void> remove(String token) async {
    if (AppConfig.isDemo) return;
    await _ref
        .read(supabaseProvider)
        .from('device_tokens')
        .delete()
        .eq('token', token);
  }
}

final deviceTokensProvider = Provider<DeviceTokens>((ref) => DeviceTokens(ref));

/// Uscita dall'account: prima esce dalla stanza vocale e ferma l'audio, poi rimuove
/// il token di questo telefono (finché l'utente è ancora autenticato, altrimenti i
/// permessi lo impedirebbero), poi esce.
Future<void> logout(WidgetRef ref) async {
  // Tutto da ref prima del primo await: la pagina che chiama può sparire intanto.
  final call = ref.read(voiceCallProvider.notifier);
  final player = ref.read(voicePlayerProvider.notifier);
  final focus = ref.read(audioFocusProvider.notifier);
  final removeToken = ref.read(deviceTokensProvider).remove;
  final auth = ref.read(authRepositoryProvider);
  try {
    // Motore e microfono si fermano subito; l'uscita sul server (finché si è
    // ancora autenticati) non deve bloccare il logout se la rete non risponde.
    await call.leave().timeout(const Duration(seconds: 5), onTimeout: () {});
  } catch (_) {}
  try {
    await player.stop();
  } catch (_) {}
  for (final use in AudioUse.values) {
    focus.release(use);
  }
  await PushService.instance.unsubscribe(onRemoveToken: removeToken);
  await auth.signOut();
}
