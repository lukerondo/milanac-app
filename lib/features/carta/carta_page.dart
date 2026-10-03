import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import '../presenze/attendance_repository.dart';
import '../risultati/matches_repository.dart';
import '../rosa/member.dart';
import '../rosa/member_editor.dart';
import '../rosa/rosa_repository.dart';
import '../voti/ratings_repository.dart';
import 'card_stats.dart';
import 'fut_card.dart';

/// Statistiche della carta di un membro (presenze degli ultimi 60 giorni e partite).
final cardStatsProvider = Provider.family<CardStats?, String>((ref, id) {
  final members = ref.watch(rosaProvider).value;
  final member = members?.where((m) => m.id == id).firstOrNull;
  if (member == null) return null;
  return CardStats.of(
    member,
    attendance: ref.watch(attendanceProvider).value ?? const [],
    matches: ref.watch(matchesProvider).value ?? const [],
  );
});

/// Sezione "La mia carta".
class MyCardPage extends ConsumerWidget {
  const MyCardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    if (me == null) return const Center(child: CircularProgressIndicator());
    return PlayerCardView(memberId: me.id);
  }
}

/// Carta di un compagno, aperta dalla Rosa.
class PlayerCardPage extends StatelessWidget {
  const PlayerCardPage({super.key, required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('CARTA GIOCATORE')),
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

  /// Mostra la carta base anche se c'è quella speciale di Uomo partita.
  bool _baseCard = false;

  Future<void> _share(Member m) async {
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
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
        SnackBar(content: Text('Condivisione non riuscita: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).value;
    final member = ref
        .watch(rosaProvider)
        .value
        ?.where((m) => m.id == widget.memberId)
        .firstOrNull;
    final stats = ref.watch(cardStatsProvider(widget.memberId));
    if (member == null || stats == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isMine = me?.id == member.id;
    final motm = ref.watch(recentMvpProvider(member.id));
    final isDirettivo = me?.isDirettivo ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: RepaintBoundary(
              key: _cardKey,
              child: Padding(
                // Margine per l'ombra nell'immagine condivisa.
                padding: const EdgeInsets.all(8),
                child: FutCard(
                  member: member,
                  stats: stats,
                  special: motm != null && !_baseCard ? CardSpecial.motm : null,
                ),
              ),
            ),
          ),
        ),
        if (motm != null) ...[
          const SizedBox(height: 8),
          Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Uomo partita')),
                ButtonSegment(value: true, label: Text('Carta base')),
              ],
              selected: {_baseCard},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _baseCard = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Uomo partita il ${DateFormat('d MMMM', 'it').format(motm.playedAt)} '
              '(media ${motm.average.toStringAsFixed(1)})',
              textAlign: TextAlign.center,
              style: const TextStyle(color: MilanacColors.gold),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (isMine && member.overall == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Completa la tua carta: scegli il tuo overall, il ruolo e lo stile di gioco.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MilanacColors.gold),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (isMine || isDirettivo)
              FilledButton.icon(
                onPressed: () => showCardEditor(context, member),
                icon: const Icon(Icons.edit_rounded),
                label: Text(
                  isMine ? 'Modifica la mia carta' : 'Modifica carta',
                ),
              ),
            OutlinedButton.icon(
              onPressed: _sharing ? null : () => _share(member),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Condividi'),
            ),
            if (isDirettivo && !isMine)
              TextButton.icon(
                onPressed: () => showMemberEditor(context, member),
                icon: const Icon(Icons.manage_accounts_rounded),
                label: const Text('Dati del membro'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        for (final MapEntry(:key, :value) in cardStatLegend.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$key  ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: MilanacColors.gold,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Stili di gioco proposti (si può scrivere anche altro).
const playStyleSuggestions = [
  'Finalizzatore',
  'Regista',
  'Box to box',
  'Muro',
  'Velocista',
  'Fantasista',
  'Mediano',
  'Saracinesca',
];

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
  bool _saving = false;

  @override
  void dispose() {
    _style.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final style = _style.text.trim();
    final updated = Member(
      id: widget.member.id,
      displayName: widget.member.displayName,
      role: widget.member.role,
      joinedAt: widget.member.joinedAt,
      gamertag: widget.member.gamertag,
      avatarUrl: widget.member.avatarUrl,
      active: widget.member.active,
      requestedRole: widget.member.requestedRole,
      teams: widget.member.teams,
      fieldPosition: _position,
      shirtNumber: int.tryParse(_number.text),
      overall: _overall,
      playStyle: style.isEmpty ? null : style,
      platform: _platform,
      avatarPath: widget.member.avatarPath,
      birthDate: widget.member.birthDate,
      city: widget.member.city,
      nationality: widget.member.nationality,
      preferredFoot: widget.member.preferredFoot,
    );
    try {
      await ref.read(rosaRepositoryProvider).saveCard(updated);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = Member(
      id: widget.member.id,
      displayName: widget.member.displayName,
      role: widget.member.role,
      joinedAt: widget.member.joinedAt,
      avatarUrl: widget.member.avatarUrl,
      teams: widget.member.teams,
      fieldPosition: _position,
      overall: _overall,
    );
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
            Row(
              children: [
                Text(
                  '$_overall',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: switch (tierOf(preview.overall)) {
                      CardTier.rossonera => MilanacColors.red,
                      CardTier.oro => MilanacColors.gold,
                      CardTier.argento => const Color(0xFFC9CED6),
                      _ => const Color(0xFFD9A273),
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text('OVERALL'),
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
                    decoration: const InputDecoration(labelText: 'Numero'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _style,
              maxLength: 24,
              decoration: const InputDecoration(labelText: 'Stile di gioco'),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in playStyleSuggestions)
                  ActionChip(
                    label: Text(s),
                    onPressed: () => setState(() => _style.text = s),
                  ),
              ],
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
