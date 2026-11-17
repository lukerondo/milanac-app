import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/notify_prefs.dart';
import '../../core/auth/providers.dart';
import '../../core/push/push_service.dart';
import '../rosa/rosa_repository.dart';
import 'chat_repository.dart';

/// Titolo e testo dell'avviso di un messaggio nuovo, come nelle notifiche push (funzione
/// notify): "#Generale · Luca" e il testo, oppure "📣 Avviso del Direttivo · Luca".
({String title, String body}) chatAlertText(
  ChatMessage m, {
  required String channelName,
  required String authorName,
}) {
  final text = m.isReplay
      ? '🎬 Nuovo schema con audio${m.replayTitle == null ? '' : ': ${m.replayTitle}'}'
      : m.isPoll
      ? '📊 Sondaggio: ${m.body?.trim() ?? ''}'
      : m.summary;
  return (
    title: m.isAnnouncement
        ? '📣 Avviso del Direttivo · $authorName'
        : m.isSystem
        ? '#$channelName'
        : '#$channelName · $authorName',
    body: text.length > 140 ? '${text.substring(0, 137)}…' : text,
  );
}

/// Avvisi dei messaggi nuovi mentre l'app è aperta: arrivano dal tempo reale della chat,
/// quindi anche dove le notifiche push non ci sono (telefono senza Firebase, browser senza
/// permesso). Valgono le stesse regole delle push: niente per i propri messaggi, per i
/// canali silenziati e, con "Chat e stanze vocali" spento, solo gli avvisi ufficiali; il
/// canale che si sta leggendo non avvisa (filtro di [PushService.shouldShowInApp]).
/// Resta acceso per tutta la vita dell'app (lo tiene vivo `MilanacApp`).
final chatAlertsProvider = Provider<void>((ref) {
  // Solo per chi è nel club; cambia account, si ricomincia.
  final me = ref.watch(
    profileProvider.select((p) {
      final profile = p.value;
      return profile != null && profile.isApproved ? profile.id : null;
    }),
  );
  if (me == null) return;
  // Canali, silenzi e nomi servono pronti al primo messaggio, anche se la chat non è
  // ancora stata aperta.
  ref.listen(channelsProvider, (_, _) {});
  ref.listen(mutedChannelsProvider, (_, _) {});
  ref.listen(rosaProvider, (_, _) {});
  final repo = ref.watch(chatRepositoryProvider);
  final sub = repo.watchIncoming().listen((m) {
    if (m.authorId == me) return;
    // App non in primo piano: ci pensano le notifiche di sistema.
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return;
    final channel = ref
        .read(channelsProvider)
        .value
        ?.where((c) => c.id == m.channelId)
        .firstOrNull;
    if (channel == null) return;
    if (ref.read(mutedChannelsProvider).value?.contains(channel.id) ?? false) {
      return;
    }
    final official = m.isAnnouncement || m.systemType == 'new_member';
    final prefs = ref.read(profileProvider).value?.notifyPrefs;
    if (!official && !(prefs?.isOn(NotifyCategory.chat) ?? true)) return;
    final author = ref
        .read(rosaProvider)
        .value
        ?.where((x) => x.id == m.authorId)
        .firstOrNull;
    final alert = chatAlertText(
      m,
      channelName: channel.name,
      authorName: author?.displayName ?? 'MILANAC',
    );
    if (alert.body.isEmpty) return;
    PushService.instance.showInApp(
      title: alert.title,
      body: alert.body,
      data: {
        'route': '/chat/${channel.slug}',
        'channel': channel.slug,
        'message': m.id,
      },
    );
  });
  ref.onDispose(sub.cancel);
});
