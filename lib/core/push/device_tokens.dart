import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    await client.from('device_tokens').upsert({
      'token': token,
      'user_id': userId,
      'platform': defaultTargetPlatform.name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
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

/// Uscita dall'account: prima rimuove il token di questo telefono (finché l'utente
/// è ancora autenticato, altrimenti i permessi lo impedirebbero), poi esce.
Future<void> logout(WidgetRef ref) async {
  await PushService.instance.unsubscribe(
    onRemoveToken: ref.read(deviceTokensProvider).remove,
  );
  await ref.read(authRepositoryProvider).signOut();
}
