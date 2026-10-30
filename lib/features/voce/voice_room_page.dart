import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../../shared/ui.dart';
import '../chat/chat_repository.dart';
import '../chat/voice_player.dart' show formatSeconds;
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'voice_call.dart';
import 'voice_models.dart';
import 'voice_repository.dart';

/// La stanza vocale a schermo intero, sempre scura come nella tavola (anche con
/// l'aspetto chiaro): chi c'è con la foto (alone d'oro su chi parla, microfono
/// barrato su chi è in muto), entra o esci, microfono e vivavoce.
class VoiceRoomPage extends StatelessWidget {
  const VoiceRoomPage({super.key, required this.channel});
  final Channel channel;

  // Dentro la stanza vale il tema scuro: context.pal dà i colori della tavola.
  static final _dark = buildTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Theme(
      data: _dark,
      child: _VoiceRoomView(channel: channel),
    ),
  );
}

class _VoiceRoomView extends ConsumerWidget {
  const _VoiceRoomView({required this.channel});
  final Channel channel;

  /// Il Direttivo chiude la stanza per tutti: chi è dentro esce subito.
  Future<void> _closeForEveryone(
    BuildContext context,
    WidgetRef ref,
    String roomId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Chiudere la stanza per tutti?'),
        content: const Text(
          'Chi è dentro esce subito. La stanza si potrà riaprire quando '
          'serve.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Chiudi per tutti'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(voiceRepositoryProvider).closeRoom(roomId);
      if (ref.read(voiceCallProvider).isIn(channel.id)) {
        unawaited(ref.read(voiceCallProvider.notifier).leave());
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Stanza chiusa per tutti.')),
      );
      if (context.mounted) unawaited(Navigator.of(context).maybePop());
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'Stanza non chiusa'))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final call = ref.watch(voiceCallProvider);
    final room = ref.watch(channelVoiceRoomProvider(channel.id));
    final sessions = room == null
        ? const <VoiceSession>[]
        : ref.watch(voiceParticipantsProvider(room.id));
    final members = ref.watch(rosaProvider).value ?? const <Member>[];
    final me = ref.watch(currentUserIdProvider);
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final notifier = ref.read(voiceCallProvider.notifier);
    final inThis = call.isIn(channel.id);
    final error =
        call.phase == VoicePhase.error && call.channel?.id == channel.id
        ? call.error
        : null;
    Member? memberOf(String? id) =>
        members.where((m) => m.id == id).firstOrNull;
    final opener = room == null ? null : memberOf(room.openedBy);

    final String status;
    if (inThis && call.phase == VoicePhase.connecting) {
      status = 'Entro nella stanza…';
    } else if (room != null && !inThis) {
      status = 'Stanza vocale · ${sessions.length} dentro';
    } else {
      status = 'Stanza vocale';
    }

    Widget participant(VoiceSession s) {
      final isMe = s.userId == me;
      return _Participant(
        member: memberOf(s.userId),
        isMe: isMe,
        speaking: s.agoraUid != null && call.speaking.contains(s.agoraUid),
        muted: isMe && inThis ? call.muted : s.muted,
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const GoldRule(),
          Expanded(
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Riduci la stanza a una striscia e torna alla chat',
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 30,
                          ),
                          color: p.text,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '#${channel.name.toUpperCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: sportFont,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 20,
                                  letterSpacing: 1.6,
                                  color: p.accentText,
                                ),
                              ),
                              if (inThis && call.since != null)
                                VoiceCallTimer(
                                  since: call.since!,
                                  prefix: 'Stanza vocale · ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: p.textMuted,
                                  ),
                                )
                              else
                                Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: p.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Stessa larghezza della freccia: il titolo resta al centro.
                        if (isDirettivo && room != null)
                          IconButton(
                            tooltip: 'Chiudi la stanza per tutti',
                            icon: const Icon(Icons.power_settings_new_rounded),
                            color: p.danger,
                            onPressed: () =>
                                _closeForEveryone(context, ref, room.id),
                          )
                        else
                          const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                      children: [
                        if (room == null)
                          _Empty(channel: channel)
                        else ...[
                          for (var i = 0; i < sessions.length; i += 2) ...[
                            if (i > 0) const SizedBox(height: 28),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: participant(sessions[i])),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: i + 1 < sessions.length
                                      ? participant(sessions[i + 1])
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ],
                          if (opener != null) ...[
                            const SizedBox(height: 28),
                            Text(
                              'Aperta da '
                              '${opener.id == me ? 'te' : opener.displayName} '
                              '${_ago(ref.read(clockProvider)().difference(room.openedAt))}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: p.textMuted,
                              ),
                            ),
                          ],
                        ],
                        if (error != null) ...[
                          const SizedBox(height: 24),
                          _ErrorBox(
                            message: error,
                            onRetry: () => notifier.enter(channel),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (inThis)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _RoundAction(
                                  icon: call.muted
                                      ? Icons.mic_off_rounded
                                      : Icons.mic_rounded,
                                  label: 'Microfono',
                                  semanticLabel: call.muted
                                      ? 'Riattiva il microfono'
                                      : 'Spegni il microfono',
                                  active: call.muted,
                                  onTap: notifier.toggleMute,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _RoundAction(
                                  icon: call.speakerphone
                                      ? Icons.volume_up_rounded
                                      : Icons.hearing_rounded,
                                  label: 'Vivavoce',
                                  semanticLabel: call.speakerphone
                                      ? 'Vivavoce acceso: passa all\'auricolare'
                                      : 'Accendi il vivavoce',
                                  active: call.speakerphone,
                                  onTap: notifier.toggleSpeakerphone,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _RoundAction(
                                  icon: Icons.call_end_rounded,
                                  label: 'Esci',
                                  semanticLabel: 'Esci dalla stanza',
                                  danger: true,
                                  onTap: () {
                                    // La pagina si chiude subito: motore e
                                    // microfono si fermano adesso, l'uscita sul
                                    // server continua da sola (senza rete la
                                    // chiude il server dopo qualche minuto).
                                    unawaited(
                                      notifier.leave().catchError(
                                        (Object _) {},
                                      ),
                                    );
                                    Navigator.of(context).maybePop();
                                  },
                                ),
                              ),
                            ],
                          )
                        else
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed: () => notifier.enter(channel),
                            icon: const Icon(Icons.headphones_rounded),
                            label: Text(
                              room == null
                                  ? 'Apri la stanza'
                                  : 'Entra nella stanza',
                            ),
                          ),
                        if (call.isActive && !inThis && call.channel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              'Sei già nella stanza di #${call.channel!.name}: '
                              'entrando qui ne esci.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: p.textMuted,
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        Text(
                          'I minuti contano sui 10.000 gratuiti del mese',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: p.textDisabled),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "adesso", "1 minuto fa", "12 minuti fa", "2 ore fa".
  static String _ago(Duration d) {
    final m = d.inMinutes;
    if (m < 1) return 'adesso';
    if (m == 1) return '1 minuto fa';
    if (m < 60) return '$m minuti fa';
    final h = d.inHours;
    return h == 1 ? 'un\'ora fa' : '$h ore fa';
  }
}

/// Stanza chiusa: l'invito ad aprirla.
class _Empty extends StatelessWidget {
  const _Empty({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.surfaceHigh,
            border: Border.all(color: p.border),
          ),
          child: Icon(Icons.headphones_rounded, size: 48, color: p.accentText),
        ),
        const SizedBox(height: 20),
        Text(
          'Nessuno è in stanza. Aprila tu: chi è in #${channel.name} riceve '
          'un avviso ed entra con un tocco.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, height: 1.4, color: p.textSecondary),
        ),
      ],
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
    final p = context.pal;
    final m = member;
    final name = isMe
        ? 'Tu'
        : m == null
        ? '?'
        : (m.firstName ?? m.displayName.split(' ').first);
    final status = speaking
        ? 'Sta parlando'
        : muted
        ? 'Microfono spento'
        : 'In ascolto';
    return Semantics(
      label: '$name, ${status.toLowerCase()}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: speaking ? p.accent : Colors.transparent,
                    width: 4,
                  ),
                  boxShadow: [
                    if (speaking)
                      BoxShadow(
                        color: p.accent.withValues(alpha: .18),
                        spreadRadius: 6,
                      ),
                  ],
                ),
                child: m == null
                    ? CircleAvatar(
                        radius: 52,
                        backgroundColor: p.surfaceHigh,
                        child: Icon(
                          Icons.person_rounded,
                          size: 48,
                          color: p.textMuted,
                        ),
                      )
                    : MemberAvatar(member: m, radius: 52),
              ),
              if (muted)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.surfaceHigher,
                      border: Border.all(color: p.bg, width: 2),
                    ),
                    child: Icon(
                      Icons.mic_off_rounded,
                      size: 18,
                      color: p.danger,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: p.text,
            ),
          ),
          Text(
            status,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: speaking ? p.accentText : p.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Azione tonda in basso (Microfono, Vivavoce, Esci): oro quando è attiva,
/// rossa per uscire.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.active,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool? active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final on = active ?? false;
    final background = danger
        ? MilanacColors.danger
        : on
        ? p.accent
        : p.surfaceHigh;
    final foreground = danger
        ? Colors.white
        : on
        ? p.onAccent
        : p.text;
    return Semantics(
      button: true,
      toggled: active,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: background,
                  border: danger || on
                      ? null
                      : Border.all(color: p.borderStrong),
                ),
                child: Icon(icon, size: danger ? 30 : 28, color: foreground),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: p.dangerBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: p.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 15, height: 1.3, color: p.text),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      ),
    );
  }
}

/// Durata della propria chiamata ("Stanza vocale · 12:04"), aggiornata ogni secondo.
class VoiceCallTimer extends ConsumerStatefulWidget {
  const VoiceCallTimer({
    super.key,
    required this.since,
    this.prefix = '',
    this.style,
  });
  final DateTime since;
  final String prefix;
  final TextStyle? style;

  @override
  ConsumerState<VoiceCallTimer> createState() => _VoiceCallTimerState();
}

class _VoiceCallTimerState extends ConsumerState<VoiceCallTimer> {
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
      '${widget.prefix}${formatSeconds(seconds)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (widget.style ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
