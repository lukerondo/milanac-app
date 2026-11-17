import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/local_flags.dart';
import '../../core/theme.dart';
import '../../shared/gold_loader.dart';
import '../carta/card_stats.dart';
import '../carta/carta_page.dart';
import '../carte/special_cards_repository.dart';
import '../risultati/matches_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import '../traguardi/achievements.dart';
import '../traguardi/achievements_view.dart';
import 'walkout_page.dart';

/// Chiave dell'ultimo overall per cui il giocatore ha visto il walkout su questo telefono.
String walkoutKey(String memberId) => 'walkout.overall.$memberId';

/// La carta speciale [cardId] si festeggia (prima volta su questo telefono)? Se sì, la
/// segna come festeggiata. Si ricordano tutte le carte festeggiate, non solo l'ultima:
/// se la più recente sparisce (partita eliminata, blu che cade) o cambia reparto, quella
/// di prima non si festeggia di nuovo. La chiave delle versioni precedenti (solo l'ultima
/// carta vista) vale ancora per chi aggiorna l'app.
Future<bool> firstTimeSpecialCard(
  LocalFlags flags,
  String memberId,
  String cardId,
) async {
  final key = 'special.celebrated.$memberId';
  final celebrated = (await flags.getList(key)).toList();
  final legacy = await flags.getString('special.seen.$memberId');
  if (legacy != null && !celebrated.contains(legacy)) celebrated.add(legacy);
  if (celebrated.contains(cardId)) return false;
  await flags.setList(key, [
    // Le ultime 50 bastano (una carta vale 7 giorni).
    ...celebrated.skip(math.max(0, celebrated.length - 49)),
    cardId,
  ]);
  return true;
}

/// Le feste (walkout, traguardi) partono da sole? Spente in demo e nei test, dove il
/// walkout si apre comunque dalla carta; le prove dell'ingresso le accendono.
final celebrationsEnabledProvider = Provider<bool>((ref) => !AppConfig.isDemo);

/// Vero da quando chi si è appena registrato accetta il regolamento a quando parte il
/// suo walkout: è l'ultimo passo dell'ingresso nel club. In quel tratto la Home resta
/// coperta ("Prepariamo la tua carta"), così la prima cosa che vede è la sua carta.
final entranceProvider = NotifierProvider<EntranceNotifier, bool>(
  EntranceNotifier.new,
);

class EntranceNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Regolamento accettato da chi non era ancora nel club.
  void begin() => state = true;

  /// Walkout partito (o non dovuto, o dati mai arrivati): l'ingresso è finito.
  void end() => state = false;
}

/// Fa partire, una volta sola per telefono:
/// - il walkout quando il giocatore entra nel club (prima apertura dopo l'approvazione)
///   o quando il suo overall sale (anche se lo alza il Direttivo, in tempo reale);
/// - la festa per i traguardi appena sbloccati.
/// In demo/test resta spento (il walkout si apre comunque dalla carta).
class Celebrations extends ConsumerStatefulWidget {
  const Celebrations({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<Celebrations> createState() => _CelebrationsState();
}

class _CelebrationsState extends ConsumerState<Celebrations> {
  bool _running = false;

  /// Un controllo chiesto mentre ce n'era uno in corso: si rifà appena finisce (i dati
  /// arrivati nel frattempo non restano senza festa).
  bool _again = false;

  /// L'account per cui gli ascolti di rosa e traguardi sono già partiti.
  String? _listeningFor;

  /// La copertura della Home per chi è appena entrato, finché non parte il walkout.
  OverlayEntry? _cover;
  final _coverOn = ValueNotifier(true);
  Timer? _coverTimeout;

  /// Quanto si aspetta la carta di chi è appena entrato (rosa e statistiche dal server)
  /// prima di mostrare la Home lo stesso: il walkout parte poi appena arrivano.
  static const entranceTimeout = Duration(seconds: 8);

  bool get _enabled => ref.read(celebrationsEnabledProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(entranceProvider)) _showCover();
      _check();
    });
  }

  @override
  void dispose() {
    _coverTimeout?.cancel();
    _removeCover();
    _coverOn.dispose();
    super.dispose();
  }

  void _showCover() {
    if (_cover != null || !mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (!_enabled || overlay == null) {
      // Senza feste (demo) non c'è niente da aspettare.
      ref.read(entranceProvider.notifier).end();
      return;
    }
    _coverOn.value = true;
    final entry = OverlayEntry(
      builder: (_) => _EntranceCover(visible: _coverOn, onGone: _removeCover),
    );
    _cover = entry;
    overlay.insert(entry);
    _coverTimeout = Timer(entranceTimeout, _endEntrance);
  }

  /// L'ingresso è finito (walkout partito, già visto su questo telefono, o dati mai
  /// arrivati): la copertura sfuma e si toglie.
  void _endEntrance() {
    _coverTimeout?.cancel();
    _coverTimeout = null;
    if (!mounted) return;
    if (ref.read(entranceProvider)) ref.read(entranceProvider.notifier).end();
    if (_cover != null) _coverOn.value = false;
  }

  void _removeCover() {
    _cover
      ?..remove()
      ..dispose();
    _cover = null;
  }

  /// Il walkout di benvenuto. Prima parte, poi si segna come visto: se l'app si chiude
  /// nel mezzo lo si rivede, invece di perderlo. Per chi è appena entrato arriva sotto
  /// la copertura, che sfuma subito: la Home si vede solo dopo la carta.
  Future<void> _welcome(
    LocalFlags flags,
    String key,
    String current,
    Member member,
    CardStats stats,
  ) async {
    final covered = _cover != null && _coverOn.value;
    final shown = showWalkout(
      context,
      member: member,
      stats: stats,
      immediate: covered,
    );
    await flags.setString(key, current);
    _endEntrance();
    await shown;
  }

  Future<void> _check() async {
    if (!_enabled || !mounted) return;
    if (_running) {
      _again = true;
      return;
    }
    final me = ref.read(profileProvider).value;
    if (me == null || !me.isApproved) return;
    final member = ref
        .read(rosaProvider)
        .value
        ?.where((m) => m.id == me.id)
        .firstOrNull;
    final stats = ref.read(cardStatsProvider(me.id));
    if (member == null || stats == null) return;

    _running = true;
    try {
      final flags = ref.read(localFlagsProvider);
      final key = walkoutKey(me.id);
      final seen = await flags.getString(key);
      final current = member.overall?.toString() ?? '-';
      final previous = seen == null ? null : int.tryParse(seen);
      if (seen == null) {
        if (mounted) await _welcome(flags, key, current, member, stats);
      } else if (member.overall != null && member.overall! > (previous ?? 0)) {
        await flags.setString(key, current);
        if (mounted) {
          await showWalkout(
            context,
            member: member,
            stats: stats,
            previousOverall: previous,
          );
        }
      } else if (seen != current) {
        await flags.setString(key, current);
      }
      // Il walkout può restare aperto a lungo: se intanto la Home non c'è più, basta.
      if (!mounted) return;
      // I dati ci sono e il walkout di benvenuto è partito (o era già stato visto):
      // l'ingresso è finito comunque.
      _endEntrance();

      // Carta speciale ricevuta (nero/oro o blu elettrico): walkout dedicato.
      final special = ref.read(activeSpecialCardProvider(me.id));
      if (special != null && mounted) {
        if (await firstTimeSpecialCard(flags, me.id, special.id)) {
          final match = ref
              .read(matchesProvider)
              .value
              ?.where((m) => m.id == special.matchId)
              .firstOrNull;
          if (mounted) {
            await showWalkout(
              context,
              member: member,
              stats: stats,
              special: special.kind,
              bonus: special.bonus,
              caption: specialCardCaption(special, match: match),
            );
          }
        }
      }

      final progress = ref.read(achievementsProvider(me.id));
      if (progress != null && mounted) {
        final seenKey = 'achievements.seen.${me.id}';
        final already = (await flags.getList(seenKey)).toSet();
        final fresh = [
          for (final p in progress)
            if (p.unlocked && !already.contains(p.achievement.id))
              p.achievement,
        ];
        if (fresh.isNotEmpty) {
          await flags.setList(seenKey, [
            ...already,
            for (final a in fresh) a.id,
          ]);
          if (mounted) await showUnlockCelebration(context, fresh);
        }
      }
    } finally {
      _running = false;
    }
    if (_again && mounted) {
      _again = false;
      unawaited(_check());
    }
  }

  @override
  Widget build(BuildContext context) {
    final meId = ref.watch(profileProvider).value?.id;
    if (meId != _listeningFor) {
      _listeningFor = meId;
      // Profilo appena arrivato (la Home si apre anche mentre carica) o account
      // cambiato: gli ascolti qui sotto partono da questo disegno, quindi quello che
      // era già arrivato prima (la rosa, le statistiche) si guarda subito dopo. Senza,
      // il walkout di chi entra aspetterebbe un cambiamento che non arriva.
      if (meId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _check());
      }
    }
    // Regolamento appena accettato con la Home già aperta sotto: si copre adesso.
    ref.listen(entranceProvider, (_, entering) {
      if (entering) _showCover();
    });
    if (meId != null) {
      // Ricontrolla quando cambiano il profilo (ingresso, overall), la rosa, le
      // statistiche della carta o i traguardi: il walkout di chi entra parte appena i
      // suoi dati sono arrivati, in qualunque ordine arrivino.
      ref.listen(
        profileProvider.select((p) => p.value?.isApproved ?? false),
        (_, _) => _check(),
      );
      ref.listen(rosaProvider, (_, _) => _check());
      ref.listen(cardStatsProvider(meId), (_, _) => _check());
      ref.listen(achievementsProvider(meId), (_, _) => _check());
      ref.listen(activeSpecialCardProvider(meId), (_, _) => _check());
    }
    return widget.child;
  }
}

/// Sopra la Home di chi è appena entrato nel club, mentre arriva la sua carta: stemma
/// e "Prepariamo la tua carta". Quando [visible] diventa falso sfuma e avvisa [onGone].
class _EntranceCover extends StatelessWidget {
  const _EntranceCover({required this.visible, required this.onGone});
  final ValueListenable<bool> visible;
  final VoidCallback onGone;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: visible,
    builder: (_, on, child) => IgnorePointer(
      // Mentre sfuma i tocchi vanno già al walkout sotto.
      ignoring: !on,
      child: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        onEnd: () {
          if (!visible.value) onGone();
        },
        child: child,
      ),
    ),
    child: AbsorbPointer(
      child: Material(
        color: MilanacColors.black,
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/stemma_256.png', width: 84),
                const SizedBox(height: 20),
                const GoldLoader(),
                const SizedBox(height: 16),
                const Text(
                  'Prepariamo la tua carta…',
                  style: TextStyle(color: MilanacColors.ivory, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
