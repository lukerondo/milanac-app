import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/haptics.dart';
import '../../core/local_flags.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/gold_loader.dart';
import '../../shared/member_photo.dart';
import '../../shared/ui.dart';
import '../carte/carte_speciali_page.dart' show openSpecialCards;
import '../carte/special_cards_repository.dart';
import '../foto/photo_upload.dart';
import '../presenze/attendance_repository.dart';
import '../risultati/matches_repository.dart';
import '../risultati/result_ui.dart';
import '../rosa/member.dart';
import '../rosa/member_editor.dart';
import '../rosa/rosa_repository.dart';
import '../traguardi/achievements_view.dart';
import '../walkout/celebrations.dart';
import '../walkout/walkout_page.dart';
import 'archetypes.dart';
import 'card_colors.dart';
import 'card_stats.dart';
import 'fut_card.dart';
import 'fut_stats.dart';
import 'live_card.dart';
import 'mini_card.dart' show cardHeroTag;
import 'playstyle_ui.dart';

/// Statistiche della carta di un membro (presenze degli ultimi 60 giorni e partite).
final cardStatsProvider = Provider.family<CardStats?, String>((ref, id) {
  final members = ref.watch(rosaProvider).value;
  final member = members?.where((m) => m.id == id).firstOrNull;
  if (members == null || member == null) return null;
  return CardStats.of(
    member,
    attendance: ref.watch(attendanceProvider).value ?? const [],
    matches: ref.watch(matchesProvider).value ?? const [],
    roster: members,
    now: ref.watch(clockProvider)(),
  );
});

/// Il contenuto del tuo profilo (pagina "Il tuo profilo"): la tua carta, i dati e i
/// traguardi.
class MyCardPage extends ConsumerWidget {
  const MyCardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    if (me == null) return const Center(child: GoldLoader());
    return PlayerCardView(memberId: me.id);
  }
}

/// Apre la carta di un compagno a schermo intero.
void openPlayerCard(BuildContext context, String memberId) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute(builder: (_) => PlayerCardPage(memberId: memberId)));

/// Carta di un compagno, aperta dalla Rosa: come il profilo, con la barra scura che
/// continua nella testata della carta.
class PlayerCardPage extends StatelessWidget {
  const PlayerCardPage({super.key, required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: context.pal.hero,
      title: const Text('CARTA GIOCATORE'),
      flexibleSpace: const Align(
        alignment: Alignment.topCenter,
        child: GoldRule(),
      ),
    ),
    body: PlayerCardView(memberId: memberId),
  );
}

class PlayerCardView extends ConsumerStatefulWidget {
  const PlayerCardView({super.key, required this.memberId});
  final String memberId;

  @override
  ConsumerState<PlayerCardView> createState() => _PlayerCardViewState();
}

class _PlayerCardViewState extends ConsumerState<PlayerCardView> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share(Member m) async {
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // La foto deve essere già sulla carta, non ancora in arrivo.
      final path = m.avatarPath;
      if (path != null) {
        await ref.read(photoBytesProvider(path).future);
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      final boundary =
          _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(png!.buffer.asUint8List(), mimeType: 'image/png'),
          ],
          fileNameOverrides: ['carta_${m.displayName.split(' ').last}.png'],
          text: 'La carta di ${m.displayName} · MILANAC Pro Club',
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Condivisione non riuscita')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _walkout(Member member, CardStats stats, SpecialCard? special) {
    final mine = ref.read(profileProvider).value?.id == member.id;
    final match = special == null
        ? null
        : ref
              .read(matchesProvider)
              .value
              ?.where((m) => m.id == special.matchId)
              .firstOrNull;
    showWalkout(
      context,
      member: member,
      stats: stats,
      special: special?.kind,
      bonus: special?.bonus ?? 0,
      caption: special == null
          ? null
          : specialCardCaption(
              special,
              match: match,
              name: mine ? null : member.displayName,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rosa = ref.watch(rosaProvider);
    final member = rosa.value
        ?.where((m) => m.id == widget.memberId)
        .firstOrNull;
    final stats = ref.watch(cardStatsProvider(widget.memberId));
    if (member == null || stats == null) {
      // Lo spinner mentre la rosa carica, poi l'errore con "Riprova" o
      // "non trovato" (prima lo spinner girava per sempre).
      if (rosa.hasError && (!rosa.isLoading || rosa.retrying)) {
        return ErrorRetry(
          message: friendlyError(
            rosa.error!,
            action: 'Caricamento non riuscito',
          ),
          onRetry: () => ref.invalidate(rosaProvider),
        );
      }
      if (rosa.isLoading) {
        return const Center(child: GoldLoader());
      }
      return ErrorRetry(
        message: 'Giocatore non trovato.',
        onRetry: () => ref.invalidate(rosaProvider),
      );
    }
    final me = ref.watch(profileProvider).value;
    // La carta speciale della settimana (se c'è) sostituisce quella normale.
    final special = ref.watch(activeSpecialCardProvider(member.id));
    final isMine = me?.id == member.id;
    final isDirettivo = me?.isDirettivo ?? false;
    final now = ref.watch(clockProvider)();

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // Testata scura con la carta, come la tavola del profilo.
        ColoredBox(
          color: context.pal.hero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 22),
            child: Column(
              children: [
                Center(
                  child: SizedBox(
                    width: FutCard.width + 16,
                    // Carta viva (riflessi, inclinazione, brillii): i riflessi stanno
                    // fuori dall'immagine condivisa, che resta la carta pulita.
                    child: LiveCard(
                      special: special?.kind,
                      padding: const EdgeInsets.all(8),
                      child: Stack(
                        children: [
                          RepaintBoundary(
                            key: _cardKey,
                            child: Padding(
                              // Margine per l'alone nell'immagine condivisa.
                              padding: const EdgeInsets.all(8),
                              // Dalla Rosa arriva in volo la mini carta.
                              child: Hero(
                                tag: cardHeroTag(member.id),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: FutCard(
                                    member: member,
                                    special: special?.kind,
                                    bonus: special?.bonus ?? 0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Sulla propria carta senza foto: l'invito a caricarla
                          // (fuori dall'immagine condivisa).
                          if (isMine && member.avatarPath == null)
                            Positioned(
                              left: 8 + FutCard.photoRect.left,
                              width: FutCard.photoRect.width,
                              top: 8 + FutCard.photoRect.top + 110,
                              child: Center(
                                child: _UploadPhotoChip(
                                  onTap: () => changeMemberPhoto(
                                    context,
                                    ref,
                                    memberId: member.id,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (special != null) ...[
                  const SizedBox(height: 4),
                  _SpecialLine(card: special, now: now),
                ],
                const SizedBox(height: 10),
                OutlinedButton(
                  // La testata è sempre scura: bordo e scritta d'oro anche nel chiaro.
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    foregroundColor: MilanacColors.goldLight,
                    side: BorderSide(
                      color: AppPalette.dark.chipBorder,
                      width: 1.5,
                    ),
                    textStyle: const TextStyle(
                      fontFamily: bodyFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () => _walkout(member, stats, special),
                  child: Text(
                    isMine ? 'Rivedi il walkout' : 'Guarda il walkout',
                  ),
                ),
              ],
            ),
          ),
        ),
        const GoldFadeLine(color: MilanacColors.goldDeep),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isMine && member.overall == null) ...[
                AppCard(
                  important: true,
                  child: Text(
                    'Il Direttivo non ha ancora assegnato il tuo overall: '
                    'intanto scegli ruolo e stile di gioco.',
                    style: TextStyle(
                      fontSize: 15,
                      color: context.pal.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _InfoCard(member: member),
              const SizedBox(height: 14),
              ArchetypeCard(
                playStyle: member.playStyle,
                codes: member.playStyles,
              ),
              _ActionsCard(
                actions: [
                  if (isMine || isDirettivo)
                    (
                      Icons.edit_rounded,
                      isMine ? 'Modifica la mia carta' : 'Modifica carta',
                      'Ruolo, statistiche, archetipo e PlayStyle',
                      () => showCardEditor(context, member),
                    ),
                  if (isMine)
                    (
                      Icons.photo_camera_rounded,
                      member.avatarPath == null
                          ? 'Carica la tua foto'
                          : 'Cambia la foto',
                      'Dalla galleria, inquadrata sulla carta',
                      () => changeMemberPhoto(
                        context,
                        ref,
                        memberId: member.id,
                        previous: member.avatarPath,
                      ),
                    ),
                  (
                    Icons.ios_share_rounded,
                    'Condividi la carta',
                    "Come immagine, nelle chat o sui social",
                    _sharing ? null : () => _share(member),
                  ),
                  if (isDirettivo && !isMine)
                    (
                      Icons.manage_accounts_rounded,
                      'Dati del membro',
                      'Squadre, ruolo nel club, gamertag',
                      () => showMemberEditor(context, member),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _StatsSection(stats: stats),
              const SizedBox(height: 24),
              AchievementsGrid(memberId: member.id),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sotto la carta: "Carta della settimana · scade tra 5 giorni" (porta alle Carte
/// speciali).
class _SpecialLine extends StatelessWidget {
  const _SpecialLine({required this.card, required this.now});
  final SpecialCard card;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final what = card.isBlue ? 'Blu elettrico' : 'Carta della settimana';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openSpecialCards(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            widthFactor: 1,
            child: Text(
              '$what · scade ${relativeDay(card.endsAt, now)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: card.isBlue ? CardColors.blueText : CardColors.goldText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gamertag, ruolo nel club, data d'ingresso e motto, una riga ciascuno.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final direttivo = member.direttivoLabel;
    final rows = [
      ('Gamertag', member.gamertag ?? '–'),
      if (member.platform != null) ('Piattaforma', member.platform!.label),
      if (member.shirtNumber != null) ('Numero', '${member.shirtNumber}'),
      (
        'Squadre',
        [
          for (final t in Team.values)
            if (member.teams.contains(t)) t.label,
        ].join(' · '),
      ),
      (
        'Ruolo nel club',
        direttivo.isEmpty
            ? member.roleLabel
            : '${member.roleLabel} · ${direttivo.toLowerCase()}',
      ),
      ('Nel club dal', DateFormat('d MMMM yyyy', 'it').format(member.joinedAt)),
      if (member.motto != null && member.motto!.trim().isNotEmpty)
        ('Motto', member.motto!.trim()),
    ];
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final (i, (label, value)) in rows.indexed) ...[
            if (i > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 15, color: p.textMuted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Le azioni sulla carta: modificarla, condividerla, i dati del membro.
class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.actions});
  final List<(IconData, String, String, VoidCallback?)> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, (icon, title, subtitle, onTap))
              in actions.indexed) ...[
            if (i > 0) const Divider(indent: 68, endIndent: 16),
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    IconTile(icon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(fontSize: 14, color: p.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: p.textMuted),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// I numeri della carta (dai dati del club), con la loro spiegazione.
class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.stats});
  final CardStats stats;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    String pct(int? v) => v == null ? '–' : '$v%';
    final cells = [
      (pct(stats.presence), 'Presenze'),
      (pct(stats.punctuality), 'Puntualità'),
      ('${stats.nights}', 'Serate'),
      ('${stats.goals}', 'Gol'),
      ('${stats.months}', 'Mesi nel club'),
      (pct(stats.winRate), 'Vittorie'),
    ];
    Widget cell((String, String) c) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Text(
              c.$1,
              style: const TextStyle(
                fontFamily: sportFont,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              c.$2,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.textMuted),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STATISTICHE',
          style: TextStyle(
            fontFamily: sportFont,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: .9,
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              Row(children: [for (final c in cells.take(3)) cell(c)]),
              const Divider(),
              Row(children: [for (final c in cells.skip(3)) cell(c)]),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Presenze, puntualità e serate degli ultimi 60 giorni; gol e vittorie '
          'delle partite delle sue squadre.',
          style: TextStyle(fontSize: 13, color: p.textMuted),
        ),
      ],
    );
  }
}

Future<void> showCardEditor(BuildContext context, Member member) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CardEditor(member: member),
    );

class _CardEditor extends ConsumerStatefulWidget {
  const _CardEditor({required this.member});
  final Member member;

  @override
  ConsumerState<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends ConsumerState<_CardEditor> {
  late int _overall = widget.member.overall ?? 70;
  late final _style = TextEditingController(text: widget.member.playStyle);
  late final _number = TextEditingController(
    text: widget.member.shirtNumber?.toString(),
  );
  late String? _position = widget.member.fieldPosition;
  late GamePlatform? _platform = widget.member.platform;
  late var _styles = [...widget.member.playStyles];
  late final _stats = {
    for (final s in FutStat.values)
      s: TextEditingController(text: widget.member.futStats[s]?.toString()),
  };
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // L'archetipo scelto si accende anche scrivendolo a mano.
    _style.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _style.dispose();
    _number.dispose();
    for (final c in _stats.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Le statistiche scritte (vuote = non indicate; quelle dell'altro ruolo restano).
  FutStats get _futStats {
    var stats = FutStats.empty;
    for (final e in _stats.entries) {
      final v = int.tryParse(e.value.text.trim());
      if (v != null && v >= FutStats.min) stats = stats.withValue(e.key, v);
    }
    return stats;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final style = _style.text.trim();
    // Numero, stile e piattaforma lasciati vuoti si cancellano davvero.
    final updated = widget.member.copyWith(
      fieldPosition: _position,
      shirtNumber: int.tryParse(_number.text.trim()),
      overall: _overall,
      playStyle: style.isEmpty ? null : style,
      playStyles: _styles,
      platform: _platform,
      futStats: _futStats,
    );
    try {
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      final messenger = ScaffoldMessenger.of(context);
      final before = widget.member.overall;
      final repo = ref.read(rosaRepositoryProvider);
      // L'overall lo decide il Direttivo: solo lui lo salva.
      if ((ref.read(profileProvider).value?.isDirettivo ?? false) &&
          _overall != before) {
        await repo.save(updated);
      } else {
        await repo.saveCard(updated);
      }
      Haptics.confirm();
      if (mounted) Navigator.of(context).pop();
      final missing = [
        if (_styles.isNotEmpty && repo.missingColumns.contains('play_styles'))
          'i PlayStyle',
        if (!updated.futStats.isEmpty &&
            repo.missingColumns.contains('fut_stats'))
          'le statistiche',
      ];
      if (missing.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Carta salvata. ${missing.join(' e ')} si vedranno quando il '
              'server del club sarà aggiornato.',
            ),
          ),
        );
      }
      // Overall salito: walkout subito (e segnato come visto su questo telefono).
      if (before != null && _overall > before && rootContext.mounted) {
        final me = ref.read(profileProvider).value;
        if (me?.id == updated.id) {
          await ref
              .read(localFlagsProvider)
              .setString(walkoutKey(updated.id), '$_overall');
        }
        final stats = ref.read(cardStatsProvider(updated.id));
        if (stats != null && rootContext.mounted) {
          await showWalkout(
            rootContext,
            member: updated,
            stats: stats,
            previousOverall: before,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Salvataggio non riuscito')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final p = context.pal;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('La carta', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (!isDirettivo)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'L\'overall lo assegna il Direttivo.',
                  style: TextStyle(fontSize: 14, color: p.textMuted),
                ),
              ),
            if (isDirettivo)
              Row(
                children: [
                  Text(
                    '$_overall',
                    style: TextStyle(
                      fontFamily: sportFont,
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Il colore del livello, come il bordo della carta.
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CardColors.tier(tierOf(_overall)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'OVERALL',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                      color: p.textMuted,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _overall.toDouble(),
                      min: 40,
                      max: 99,
                      divisions: 59,
                      label: '$_overall',
                      onChanged: (v) => setState(() => _overall = v.round()),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _position,
                    decoration: const InputDecoration(labelText: 'Ruolo'),
                    items: [
                      for (final p in fieldPositions)
                        DropdownMenuItem(value: p, child: Text(p)),
                    ],
                    onChanged: (v) => setState(() => _position = v),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _number,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(labelText: 'Numero'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _StatsEditor(position: _position, controllers: _stats),
            const SizedBox(height: 12),
            Text('Archetipo', style: Theme.of(context).textTheme.titleSmall),
            for (final area in ArchetypeArea.values) ...[
              const SizedBox(height: 8),
              Text(
                area.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: p.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final a in archetypes.where((a) => a.area == area))
                    ChoiceChip(
                      avatar: Icon(a.icon, size: 18),
                      label: Text(a.name),
                      showCheckmark: false,
                      selected: archetypeOf(_style.text)?.name == a.name,
                      onSelected: (on) => _style.text = on ? a.name : '',
                    ),
                ],
              ),
            ],
            if (archetypeOf(_style.text) case final a?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  a.description,
                  style: TextStyle(fontSize: 14, color: p.textSecondary),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _style,
              maxLength: 24,
              decoration: const InputDecoration(
                labelText: 'Stile di gioco',
                hintText: 'Un archetipo qui sopra, o scrivi il tuo',
              ),
            ),
            PlayStylePicker(
              codes: _styles,
              onChanged: (codes) => setState(() => _styles = codes),
            ),
            const SizedBox(height: 12),
            const Text('Piattaforma'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final p in GamePlatform.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: _platform == p,
                    onSelected: (on) =>
                        setState(() => _platform = on ? p : null),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Salva la carta'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le sei statistiche FUT da scrivere come nel gioco (quelle da portiere per il POR).
class _StatsEditor extends StatelessWidget {
  const _StatsEditor({required this.position, required this.controllers});
  final String? position;
  final Map<FutStat, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final stats = FutStat.forPosition(position);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          position == 'POR' ? 'Statistiche da portiere' : 'Statistiche',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 2),
        Text(
          'Da 1 a 99, come sul tuo Pro in FC. Vuote non compaiono.',
          style: TextStyle(fontSize: 14, color: p.textMuted),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: [
            for (final s in stats)
              TextField(
                key: ValueKey('statistica-${s.key}'),
                controller: controllers[s],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                style: const TextStyle(
                  fontFamily: sportFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  labelText: s.short,
                  helperText: s.label,
                  isDense: true,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Carica la tua foto" sulla propria carta senza foto.
class _UploadPhotoChip extends StatelessWidget {
  const _UploadPhotoChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: .72),
    shape: const StadiumBorder(
      side: BorderSide(color: MilanacColors.goldLight, width: 1.2),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        // Dentro il riquadro della foto: con il testo grande si rimpicciolisce.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_a_photo_rounded,
                size: 16,
                color: MilanacColors.goldLight,
              ),
              SizedBox(width: 6),
              Text(
                'Carica la tua foto',
                style: TextStyle(
                  fontFamily: bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MilanacColors.goldLight,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
