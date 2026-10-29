import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/gold_loader.dart';
import '../../shared/ui.dart';
import '../carta/card_colors.dart';
import '../risultati/result_ui.dart' show ClubCrest;
import 'trophies_repository.dart';
import 'trophy.dart';
import 'trophy_editor.dart';
import 'trophy_shape_painter.dart';

/// Albo d'oro: le stagioni in alto, il numero di trofei e l'elenco dei trofei della
/// stagione scelta, come la tavola.
class AlboDoroPage extends ConsumerStatefulWidget {
  const AlboDoroPage({super.key});

  @override
  ConsumerState<AlboDoroPage> createState() => _AlboDoroPageState();
}

class _AlboDoroPageState extends ConsumerState<AlboDoroPage> {
  String? _seasonId;

  Future<void> _add(Season? current) async {
    final savedSeason = await showTrophyEditor(
      context,
      seasonLabel: current?.label,
    );
    if (savedSeason != null && mounted) {
      setState(() => _seasonId = savedSeason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final seasons = ref.watch(seasonsProvider);
    final list = seasons.value;
    if (list == null) {
      return AsyncView(
        value: seasons,
        onRetry: () => ref.invalidate(seasonsProvider),
        data: (_) => const SizedBox.shrink(),
      );
    }
    // Le stagioni dalla più vecchia alla più recente; si parte da quella in corso.
    final ordered = List.of(list)..sort((a, b) => a.label.compareTo(b.label));
    final current = currentSeasonLabel();
    final selected = ordered.isEmpty
        ? null
        : ordered.where((s) => s.id == _seasonId).firstOrNull ??
              ordered.where((s) => s.label == current).firstOrNull ??
              ordered.last;
    final p = context.pal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (ordered.length > 1) ...[
          _SeasonPicker(
            seasons: ordered,
            selected: selected!,
            onChanged: (s) => setState(() => _seasonId = s.id),
          ),
          const SizedBox(height: 16),
        ],
        if (selected == null)
          _Empty(text: 'Ancora nessuna stagione in bacheca.', p: p)
        else
          _SeasonTrophies(season: selected, canEdit: isDirettivo),
        if (isDirettivo) ...[
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () => _add(selected),
            child: const Text('Aggiungi un trofeo'),
          ),
        ],
      ],
    );
  }
}

/// Le stagioni: a schede come la tavola, a pillole se sono tante.
class _SeasonPicker extends StatelessWidget {
  const _SeasonPicker({
    required this.seasons,
    required this.selected,
    required this.onChanged,
  });
  final List<Season> seasons;
  final Season selected;
  final ValueChanged<Season> onChanged;

  @override
  Widget build(BuildContext context) {
    if (seasons.length <= 3) {
      return SegmentedTabs(
        labels: [for (final s in seasons) s.label],
        selected: seasons.indexOf(selected),
        onSelected: (i) => onChanged(seasons[i]),
      );
    }
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        children: [
          for (final s in seasons.reversed) ...[
            FilterPill(
              label: s.label,
              selected: s.id == selected.id,
              onTap: () => onChanged(s),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, required this.p});
  final String text;
  final AppPalette p;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, height: 1.4, color: p.textSecondary),
    ),
  );
}

/// Il numero di trofei della stagione e il loro elenco.
class _SeasonTrophies extends ConsumerWidget {
  const _SeasonTrophies({required this.season, required this.canEdit});
  final Season season;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final trophies = ref.watch(trophiesProvider(season.id));
    // Trofei non arrivati: l'errore con "Riprova", non la bacheca vuota.
    if (!trophies.hasValue &&
        trophies.hasError &&
        (!trophies.isLoading || trophies.retrying)) {
      return ErrorRetry(
        message: friendlyError(
          trophies.error!,
          action: 'Caricamento non riuscito',
        ),
        onRetry: () => ref.invalidate(trophiesProvider(season.id)),
      );
    }
    final list = trophies.value;
    if (list == null) return const GoldBar();
    if (list.isEmpty) {
      return _Empty(
        text:
            'Bacheca ancora vuota per questa stagione.\n'
            'Forza MILANAC, riempiamola!',
        p: p,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CountCard(count: list.length, season: season.label),
        const SizedBox(height: 14),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, t) in list.indexed) ...[
                if (i > 0) const Divider(indent: 70),
                _TrophyRow(trophy: t, canEdit: canEdit),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "5 TROFEI nella stagione 2025/26", nero e oro con lo stemma (come una targa,
/// uguale nei due temi).
class _CountCard extends StatelessWidget {
  const _CountCard({required this.count, required this.season});
  final int count;
  final String season;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: CardColors.neroOro,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: CardColors.gold),
    ),
    child: Row(
      children: [
        Text(
          '$count',
          style: const TextStyle(
            fontFamily: sportFont,
            fontSize: 64,
            fontWeight: FontWeight.w700,
            height: 1,
            color: CardColors.goldText,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count == 1 ? 'TROFEO' : 'TROFEI',
                style: const TextStyle(
                  fontFamily: sportFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: CardColors.goldText,
                ),
              ),
              Text(
                'nella stagione $season',
                style: const TextStyle(
                  fontSize: 15,
                  color: CardColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const ClubCrest(),
      ],
    ),
  );
}

/// Riga di un trofeo: riquadro con la foto o l'icona della forma, e il nome.
class _TrophyRow extends StatelessWidget {
  const _TrophyRow({required this.trophy, required this.canEdit});
  final Trophy trophy;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // Coppe, scudetti e targhe in oro; medaglie e premi individuali in grigio.
    final prize = switch (trophy.shape) {
      TrophyShape.coppa || TrophyShape.scudetto || TrophyShape.targa => true,
      TrophyShape.medaglia || TrophyShape.stella => false,
    };
    final icon = switch (trophy.shape) {
      TrophyShape.coppa => Icons.emoji_events_rounded,
      TrophyShape.scudetto => Icons.shield_rounded,
      TrophyShape.targa => Icons.workspace_premium_rounded,
      TrophyShape.medaglia => Icons.military_tech_rounded,
      TrophyShape.stella => Icons.star_rounded,
    };
    void open() => showTrophyDetails(context, trophy, canEdit: canEdit);
    return Semantics(
      button: true,
      label: trophy.name,
      onTap: open,
      excludeSemantics: true,
      child: InkWell(
        onTap: open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  clipBehavior: Clip.antiAlias,
                  padding: trophy.hasImage
                      ? const EdgeInsets.all(4)
                      : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: prize ? p.accentTint : p.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: trophy.hasImage
                      ? TrophyVisual(trophy: trophy)
                      : Icon(
                          icon,
                          size: 22,
                          color: prize ? p.accentText : p.textSecondary,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    trophy.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Immagine caricata dal Direttivo oppure forma disegnata.
class TrophyVisual extends ConsumerStatefulWidget {
  const TrophyVisual({super.key, required this.trophy});
  final Trophy trophy;

  @override
  ConsumerState<TrophyVisual> createState() => _TrophyVisualState();
}

class _TrophyVisualState extends ConsumerState<TrophyVisual> {
  /// L'URL rifiutato (di solito scaduto) si rigenera una volta sola.
  bool _renewed = false;

  @override
  Widget build(BuildContext context) {
    final trophy = widget.trophy;
    final drawn = CustomPaint(
      painter: TrophyShapePainter(trophy.shape),
      child: const SizedBox.expand(),
    );
    if (trophy.localBytes != null) {
      return Image.memory(trophy.localBytes!, fit: BoxFit.contain);
    }
    if (trophy.imagePath == null) return drawn;
    final url = ref.watch(trophyImageUrlProvider(trophy));
    return url.when(
      loading: () => drawn,
      error: (_, _) => drawn,
      data: (u) => Image.network(
        u,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) {
          if (!_renewed) {
            _renewed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) ref.invalidate(trophyImageUrlProvider(trophy));
            });
          }
          return drawn;
        },
      ),
    );
  }
}
