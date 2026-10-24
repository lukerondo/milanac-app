import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../rosa/member.dart';
import 'chat_repository.dart';

/// Che cosa sta facendo chi scrive: un testo o un vocale.
enum TypingKind { testo, vocale }

/// "Sta scrivendo" in un canale: avvisi di passaggio, mai salvati.
abstract class TypingChannel {
  /// Chi sta scrivendo adesso (id del profilo → testo o vocale), senza sé stessi.
  /// Parte da com'è adesso.
  Stream<Map<String, TypingKind>> get typists;

  /// Si sta scrivendo (o registrando): si chiama a ogni modifica, l'avviso parte al
  /// massimo ogni [TypingTiming.every].
  void ping(TypingKind kind);

  /// Smesso: messaggio inviato, testo cancellato, registrazione finita.
  void stop();

  Future<void> dispose();
}

/// I tempi dell'avviso: chi scrive lo ripete ogni [every]; chi lo riceve lo tiene per
/// [keep] (se lo "smesso" si perde, sparisce da solo).
abstract final class TypingTiming {
  static const every = Duration(seconds: 3);
  static const keep = Duration(seconds: 6);
}

/// L'avviso viaggia sul canale privato Realtime `chat:<id del canale>`: lo usa solo
/// chi vede il canale (regole in `realtime.messages`, migrazione 0026).
class RealtimeTypingChannel implements TypingChannel {
  RealtimeTypingChannel(this._client, String channelId, this._me)
    : _channel = _client.channel(
        'chat:$channelId',
        opts: const RealtimeChannelConfig(private: true),
      ) {
    _channel
      ..onBroadcast(event: _event, callback: _received)
      ..subscribe();
  }

  static const _event = 'scrive';
  final SupabaseClient _client;
  final RealtimeChannel _channel;
  final String _me;
  final _typists = <String, (TypingKind, DateTime)>{};
  final _out = StreamController<Map<String, TypingKind>>.broadcast();
  Timer? _expiry;
  DateTime? _lastPing;
  TypingKind? _lastKind;

  @override
  Stream<Map<String, TypingKind>> get typists async* {
    yield _current;
    yield* _out.stream;
  }

  Map<String, TypingKind> get _current => {
    for (final MapEntry(:key, :value) in _typists.entries) key: value.$1,
  };

  @override
  void ping(TypingKind kind) {
    final now = DateTime.now();
    final last = _lastPing;
    if (kind == _lastKind &&
        last != null &&
        now.difference(last) < TypingTiming.every) {
      return;
    }
    _lastPing = now;
    _lastKind = kind;
    _send({'user': _me, 'kind': kind.name, 'on': true});
  }

  @override
  void stop() {
    if (_lastPing == null) return;
    _lastPing = null;
    _lastKind = null;
    _send({'user': _me, 'on': false});
  }

  void _send(Map<String, dynamic> payload) {
    unawaited(
      _channel
          .sendBroadcastMessage(event: _event, payload: payload)
          .then((_) {}, onError: (Object _) {}),
    );
  }

  void _received(Map<String, dynamic> message) {
    final inner = message['payload'];
    final data = inner is Map ? inner : message;
    final user = data['user'];
    if (user is! String || user == _me) return;
    if (data['on'] == true) {
      final kind = TypingKind.values
          .where((k) => k.name == data['kind'])
          .firstOrNull;
      _typists[user] = (
        kind ?? TypingKind.testo,
        DateTime.now().add(TypingTiming.keep),
      );
    } else {
      _typists.remove(user);
    }
    _changed();
  }

  void _changed() {
    if (!_out.isClosed) _out.add(_current);
    _expiry?.cancel();
    _expiry = null;
    if (_typists.isEmpty) return;
    final next = _typists.values
        .map((t) => t.$2)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    _expiry = Timer(next.difference(DateTime.now()), () {
      final now = DateTime.now();
      _typists.removeWhere((_, t) => !t.$2.isAfter(now));
      _changed();
    });
  }

  @override
  Future<void> dispose() async {
    stop();
    _expiry?.cancel();
    await _out.close();
    try {
      await _client.removeChannel(_channel);
    } catch (_) {}
  }
}

/// Demo e test: nessuna rete; [simulate] fa scrivere qualcun altro, [pings] e [stops]
/// contano gli avvisi che partirebbero.
class DemoTypingChannel implements TypingChannel {
  final _typists = <String, TypingKind>{};
  final _out = StreamController<Map<String, TypingKind>>.broadcast();
  var pings = 0;
  var stops = 0;
  TypingKind? lastKind;

  @override
  Stream<Map<String, TypingKind>> get typists async* {
    yield Map.of(_typists);
    yield* _out.stream;
  }

  /// [userId] scrive ([kind]) o smette (null).
  void simulate(String userId, TypingKind? kind) {
    if (kind == null) {
      _typists.remove(userId);
    } else {
      _typists[userId] = kind;
    }
    if (!_out.isClosed) _out.add(Map.of(_typists));
  }

  @override
  void ping(TypingKind kind) {
    pings++;
    lastKind = kind;
  }

  @override
  void stop() => stops++;

  /// La conversazione si chiude: il canale resta (si riapre uguale).
  @override
  Future<void> dispose() async {}

  /// Chiude davvero (la demo finisce).
  void close() => _out.close();
}

/// Il canale "sta scrivendo" della conversazione aperta (si chiude uscendo).
final typingChannelProvider = Provider.autoDispose
    .family<TypingChannel, String>((ref, channelId) {
      final typing = ref.watch(chatRepositoryProvider).typing(channelId);
      ref.onDispose(() => unawaited(typing.dispose()));
      return typing;
    });

final typistsProvider = StreamProvider.autoDispose
    .family<Map<String, TypingKind>, String>(
      (ref, channelId) => ref.watch(typingChannelProvider(channelId)).typists,
    );

/// "Marco sta scrivendo…", "Marco registra un vocale…", "Marco e Luca stanno
/// scrivendo…", "3 persone stanno scrivendo…"; null se nessuno.
String? typingLabel(
  Map<String, TypingKind> typists,
  Map<String, Member> names,
) {
  if (typists.isEmpty) return null;
  String name(String id) {
    final m = names[id];
    if (m == null) return 'Qualcuno';
    return m.firstName ?? m.displayName.split(' ').first;
  }

  final ids = typists.keys.toList()..sort();
  if (ids.length == 1) {
    return typists[ids.single] == TypingKind.vocale
        ? '${name(ids.single)} registra un vocale'
        : '${name(ids.single)} sta scrivendo';
  }
  if (ids.length == 2) {
    return '${name(ids[0])} e ${name(ids[1])} stanno scrivendo';
  }
  return '${ids.length} persone stanno scrivendo';
}

/// Il testo con i tre puntini che si accendono uno dopo l'altro.
class TypingText extends StatefulWidget {
  const TypingText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<TypingText> createState() => _TypingTextState();
}

class _TypingTextState extends State<TypingText>
    with SingleTickerProviderStateMixin {
  late final _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '${widget.text}…',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          ),
        ),
        AnimatedBuilder(
          animation: _dots,
          builder: (context, _) {
            final step = (_dots.value * 4).floor();
            return Text(
              '${'.' * step.clamp(0, 3)}${' ' * (3 - step.clamp(0, 3))}',
              style: widget.style,
            );
          },
        ),
      ],
    ),
  );
}
