import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import '../chat/chat_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'voice_call.dart';
import 'voice_models.dart';
import 'voice_repository.dart';
import 'voice_room_page.dart';

export 'voice_room_page.dart' show VoiceRoomPage;

/// Apre la stanza vocale del canale a schermo intero, sopra le schede.
Future<void> showVoiceRoom(BuildContext context, Channel channel) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'stanza-vocale'),
        builder: (_) => VoiceRoomPage(channel: channel),
      ),
    );

/// Azione "Stanza vocale" nella barra della conversazione (sempre scura): cuffie
/// dorate, con il numero di chi c'è, se la stanza è aperta.
class VoiceRoomButton extends ConsumerWidget {
  const VoiceRoomButton({super.key, required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(channelVoiceRoomProvider(channel.id));
    final count = room == null
        ? 0
        : ref.watch(voiceParticipantsProvider(room.id)).length;
    final live = room != null || ref.watch(voiceCallProvider).isIn(channel.id);
    return IconButton(
      tooltip: 'Stanza vocale',
      onPressed: () => showVoiceRoom(context, channel),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: Icon(
          Icons.headphones_rounded,
          size: 22,
          color: live ? MilanacColors.goldLight : MilanacColors.ivoryMuted,
        ),
      ),
    );
  }
}

/// Card della stanza vocale del canale: "Stanza vocale aperta · Milan AC — Marco e
/// Luca sono dentro — Entra"; se ci sei, la tua chiamata ridotta a striscia
/// (microfono ed esci sempre a portata di dito, un tocco riapre la stanza).
class VoiceRoomBanner extends ConsumerWidget {
  const VoiceRoomBanner({
    super.key,
    required this.channel,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 2),
  });
  final Channel channel;

  /// Margine intorno alla card (nell'elenco dei canali si può azzerare).
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(voiceCallProvider);
    final notifier = ref.read(voiceCallProvider.notifier);
    if (call.isIn(channel.id)) {
      final connecting = call.phase == VoicePhase.connecting;
      return Padding(
        padding: padding,
        child: _LiveCard(
          title: 'Sei nella stanza vocale',
          subtitle: connecting || call.since == null
              ? const Text('Entro nella stanza…')
              : VoiceCallTimer(
                  since: call.since!,
                  prefix: '#${channel.name} · ',
                ),
          onTap: () => showVoiceRoom(context, channel),
          trailing: [
            _StripButton(
              tooltip: call.muted
                  ? 'Riattiva il microfono'
                  : 'Spegni il microfono',
              icon: call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              background: call.muted
                  ? MilanacColors.gold
                  : AppPalette.dark.surfaceHigher,
              foreground: call.muted ? MilanacColors.ink : MilanacColors.ivory,
              onPressed: notifier.toggleMute,
            ),
            const SizedBox(width: 8),
            _StripButton(
              tooltip: 'Esci dalla stanza',
              icon: Icons.call_end_rounded,
              background: MilanacColors.danger,
              foreground: Colors.white,
              onPressed: notifier.leave,
            ),
          ],
        ),
      );
    }
    final room = ref.watch(channelVoiceRoomProvider(channel.id));
    if (room == null) return const SizedBox.shrink();
    final inside = _whoIsInside(
      ref.watch(voiceParticipantsProvider(room.id)),
      ref.watch(rosaProvider).value ?? const <Member>[],
      ref.watch(currentUserIdProvider),
    );
    return Padding(
      padding: padding,
      child: _LiveCard(
        // Se va a capo, il nome del canale resta intero sulla seconda riga.
        title: 'Stanza vocale aperta · ${channel.name.replaceAll(' ', ' ')}',
        subtitle: Text(inside),
        onTap: () => showVoiceRoom(context, channel),
        trailing: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MilanacColors.gold,
              foregroundColor: MilanacColors.ink,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              textStyle: const TextStyle(
                fontFamily: bodyFont,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              notifier.enter(channel);
              showVoiceRoom(context, channel);
            },
            child: const Text('Entra'),
          ),
        ],
      ),
    );
  }

  /// "Marco e Luca sono dentro" (tu escluso: la card è per chi non è dentro).
  static String _whoIsInside(
    List<VoiceSession> sessions,
    List<Member> members,
    String? me,
  ) {
    final others = sessions.where((s) => s.userId != me).toList();
    if (others.isEmpty) {
      return sessions.isEmpty ? 'Ancora nessuno dentro' : 'Ci sei tu';
    }
    final names = <String>[];
    for (final s in others) {
      final m = members.where((m) => m.id == s.userId).firstOrNull;
      // Rosa non ancora arrivata: basta il numero.
      if (m == null) {
        return others.length == 1
            ? '1 persona dentro'
            : '${others.length} persone dentro';
      }
      names.add(m.firstName ?? m.displayName.split(' ').first);
    }
    if (names.length == 1) return '${names.single} è dentro';
    final shown = names.length <= 3
        ? names
        : [...names.take(2), 'altri ${names.length - 2}'];
    return '${shown.take(shown.length - 1).join(', ')} e ${shown.last} '
        'sono dentro';
  }
}

/// La card della tavola 12: fondo "hero" sempre scuro con il bordo oro, le cuffie
/// nel cerchio dorato, titolo e sottotitolo, le azioni a destra.
class _LiveCard extends StatelessWidget {
  const _LiveCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.trailing,
  });
  final String title;
  final Widget subtitle;
  final VoidCallback onTap;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // La card resta scura anche con l'aspetto chiaro: dettagli dalla tavola scura.
    const dark = AppPalette.dark;
    return AppCard(
      hero: true,
      borderColor: p.isDark ? p.importantBorder : null,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark.accentTint,
              border: Border.all(color: dark.importantBorder),
            ),
            child: const Icon(
              Icons.headphones_rounded,
              size: 22,
              color: HeroText.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: HeroText.primary,
                  ),
                ),
                DefaultTextStyle.merge(
                  style: const TextStyle(
                    fontSize: 14,
                    color: HeroText.secondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: subtitle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ...trailing,
        ],
      ),
    );
  }
}

/// Pulsante tondo della striscia (microfono, esci): 44 px, colori fissi perché
/// la card è sempre scura.
class _StripButton extends StatelessWidget {
  const _StripButton({
    required this.tooltip,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      fixedSize: const Size(44, 44),
    ),
    icon: Icon(icon, size: 22),
  );
}
