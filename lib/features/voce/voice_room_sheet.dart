import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../chat/chat_repository.dart';
import '../chat/voice_player.dart' show formatSeconds;
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'voice_call.dart';
import 'voice_models.dart';
import 'voice_repository.dart';

/// Apre il foglio della stanza vocale del canale.
Future<void> showVoiceRoom(BuildContext context, Channel channel) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MilanacColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => VoiceRoomSheet(channel: channel),
    );

/// Cuffie nella barra della chat: dorate (con il numero di chi c'è) se la
/// stanza è aperta.
class VoiceRoomButton extends ConsumerWidget {
  const VoiceRoomButton({super.key, required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(channelVoiceRoomProvider(channel.id));
    final count = room == null
        ? 0
        : ref.watch(voiceParticipantsProvider(room.id)).length;
    final inRoom = ref.watch(voiceCallProvider).isIn(channel.id);
    return IconButton(
      tooltip: 'Stanza vocale',
      onPressed: () => showVoiceRoom(context, channel),
      icon: Badge(
        isLabelVisible: count > 0,
        backgroundColor: MilanacColors.gold,
        textColor: Colors.black,
        label: Text('$count'),
        child: Icon(
          Icons.headset_mic_rounded,
          color: room != null || inRoom ? MilanacColors.gold : Colors.white70,
        ),
      ),
    );
  }
}

/// Striscia sotto la barra: "stanza aperta, entra" oppure la propria chiamata
/// in corso (microfono ed esci sempre a portata di dito).
class VoiceRoomBanner extends ConsumerWidget {
  const VoiceRoomBanner({super.key, required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(voiceCallProvider);
    final room = ref.watch(channelVoiceRoomProvider(channel.id));
    final notifier = ref.read(voiceCallProvider.notifier);
    if (call.isIn(channel.id)) {
      return Material(
        color: MilanacColors.red,
        child: InkWell(
          onTap: () => showVoiceRoom(context, channel),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.headset_mic_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    call.phase == VoicePhase.connecting
                        ? 'Entro nella stanza…'
                        : 'Sei nella stanza vocale',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (call.since != null) _Elapsed(since: call.since!),
                IconButton(
                  tooltip: call.muted
                      ? 'Riattiva il microfono'
                      : 'Spegni il microfono',
                  icon: Icon(
                    call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: Colors.white,
                  ),
                  onPressed: notifier.toggleMute,
                ),
                IconButton(
                  tooltip: 'Esci dalla stanza',
                  icon: const Icon(Icons.call_end_rounded, color: Colors.white),
                  onPressed: notifier.leave,
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (room == null) return const SizedBox.shrink();
    final count = ref.watch(voiceParticipantsProvider(room.id)).length;
    return Material(
      color: MilanacColors.gold.withValues(alpha: .14),
      child: InkWell(
        onTap: () => showVoiceRoom(context, channel),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              const Icon(
                Icons.headset_mic_rounded,
                color: MilanacColors.gold,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Stanza vocale aperta · $count dentro',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.tonal(
                onPressed: () {
                  notifier.enter(channel);
                  showVoiceRoom(context, channel);
                },
                child: const Text('Entra'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il foglio della stanza: chi c'è (con il volto, verde chi parla, microfono
/// barrato chi è in muto), entra/esci, microfono e vivavoce.
class VoiceRoomSheet extends ConsumerWidget {
  const VoiceRoomSheet({super.key, required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(voiceCallProvider);
    final room = ref.watch(channelVoiceRoomProvider(channel.id));
    final sessions = room == null
        ? const <VoiceSession>[]
        : ref.watch(voiceParticipantsProvider(room.id));
    final members = ref.watch(rosaProvider).value ?? const <Member>[];
    final me = ref.watch(profileProvider).value?.id;
    final notifier = ref.read(voiceCallProvider.notifier);
    final inThis = call.isIn(channel.id);
    final connecting =
        call.phase == VoicePhase.connecting && call.channel?.id == channel.id;
    final error =
        call.phase == VoicePhase.error && call.channel?.id == channel.id
        ? call.error
        : null;
    final opener = room == null
        ? null
        : members.where((m) => m.id == room.openedBy).firstOrNull;
    final openedMinutes = room == null
        ? 0
        : ref.read(clockProvider)().difference(room.openedAt).inMinutes;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  Icons.headset_mic_rounded,
                  color: MilanacColors.gold,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STANZA VOCALE',
                        style: TextStyle(
                          fontFamily: sportFont,
                          fontSize: 18,
                          letterSpacing: 2,
                          color: MilanacColors.gold,
                        ),
                      ),
                      Text(
                        '#${channel.name}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (room != null)
                  Text(
                    '${sessions.length} dentro',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (room == null)
              Text(
                'Nessuno è in stanza. Aprila tu: chi è in #${channel.name} '
                'riceve un avviso ed entra con un tocco.',
                style: const TextStyle(color: Colors.white70, height: 1.35),
              )
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  for (final s in sessions)
                    _Participant(
                      member: members
                          .where((m) => m.id == s.userId)
                          .firstOrNull,
                      isMe: s.userId == me,
                      speaking:
                          s.agoraUid != null &&
                          call.speaking.contains(s.agoraUid),
                      muted: s.userId == me && inThis ? call.muted : s.muted,
                    ),
                ],
              ),
              if (opener != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    openedMinutes < 1
                        ? 'Aperta da ${opener.displayName} adesso'
                        : 'Aperta da ${opener.displayName} · $openedMinutes min fa',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
            ],
            if (error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  color: MilanacColors.red.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: MilanacColors.redText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(error)),
                    TextButton(
                      onPressed: () => notifier.enter(channel),
                      child: const Text('Riprova'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (inThis)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundAction(
                    icon: call.muted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    label: 'Microfono',
                    active: call.muted,
                    onTap: notifier.toggleMute,
                  ),
                  _RoundAction(
                    icon: call.speakerphone
                        ? Icons.volume_up_rounded
                        : Icons.hearing_rounded,
                    label: 'Vivavoce',
                    active: !call.speakerphone,
                    onTap: notifier.toggleSpeakerphone,
                  ),
                  _RoundAction(
                    icon: Icons.call_end_rounded,
                    label: 'Esci',
                    color: MilanacColors.red,
                    onTap: () async {
                      await notifier.leave();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: connecting ? null : () => notifier.enter(channel),
                icon: connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.headset_mic_rounded),
                label: Text(
                  connecting
                      ? 'Entro…'
                      : room == null
                      ? 'Apri la stanza'
                      : 'Entra nella stanza',
                ),
              ),
            if (call.isActive && !inThis && call.channel != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Sei già nella stanza di #${call.channel!.name}: entrando qui '
                  'ne esci.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            const SizedBox(height: 10),
            const Text(
              'I minuti in stanza contano sui 10.000 mensili del piano gratuito '
              'del club.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _Participant extends StatelessWidget {
  const _Participant({
    required this.member,
    required this.isMe,
    required this.speaking,
    required this.muted,
  });
  final Member? member;
  final bool isMe;
  final bool speaking;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final name = isMe
        ? 'Tu'
        : m == null
        ? '?'
        : (m.firstName ?? m.displayName.split(' ').first);
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: speaking ? Colors.greenAccent : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: m == null
                    ? const CircleAvatar(
                        radius: 26,
                        backgroundColor: MilanacColors.surfaceHigh,
                        child: Icon(
                          Icons.person_rounded,
                          color: Colors.white54,
                        ),
                      )
                    : MemberAvatar(member: m, radius: 26),
              ),
              if (muted)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mic_off_rounded,
                      size: 14,
                      color: MilanacColors.redText,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
              color: speaking ? Colors.greenAccent : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  color ??
                  (active ? MilanacColors.gold : MilanacColors.surfaceHigh),
            ),
            child: Icon(
              icon,
              size: 26,
              color: color == null && active ? Colors.black : Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}

/// Cronometro della chiamata (si aggiorna ogni secondo).
class _Elapsed extends ConsumerStatefulWidget {
  const _Elapsed({required this.since});
  final DateTime since;

  @override
  ConsumerState<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends ConsumerState<_Elapsed> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = ref
        .read(clockProvider)()
        .difference(widget.since)
        .inSeconds
        .clamp(0, 359999);
    return Text(
      formatSeconds(seconds),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
