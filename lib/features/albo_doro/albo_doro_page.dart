import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import 'scene_painters.dart';
import 'trophies_repository.dart';
import 'trophy.dart';
import 'trophy_editor.dart';

const _perShelf = 4;
const _minShelves = 3;

class AlboDoroPage extends ConsumerStatefulWidget {
  const AlboDoroPage({super.key});

  @override
  ConsumerState<AlboDoroPage> createState() => _AlboDoroPageState();
}

class _AlboDoroPageState extends ConsumerState<AlboDoroPage> {
  String? _seasonId;

  /// Inclinazione del telefono (-1..1) per l'effetto profondità.
  Offset _tilt = Offset.zero;
  StreamSubscription<AccelerometerEvent>? _sensor;

  @override
  void initState() {
    super.initState();
    try {
      _sensor =
          accelerometerEventStream(
            samplingPeriod: SensorInterval.uiInterval,
          ).listen(
            (e) {
              final target = Offset(
                (-e.x / 6).clamp(-1, 1),
                ((e.y - 6) / 6).clamp(-1, 1),
              );
              // Media mobile per un movimento morbido.
              final next = Offset.lerp(_tilt, target, .12)!;
              if (mounted && (next - _tilt).distance > .005) {
                setState(() => _tilt = next);
              }
            },
            onError: (_) {}, // sensore non disponibile (web, emulatori, test)
            cancelOnError: true,
          );
    } catch (_) {
      // Piattaforma senza sensori.
    }
  }

  @override
  void dispose() {
    _sensor?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final seasons = ref.watch(seasonsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isDirettivo
          ? FloatingActionButton.extended(
              backgroundColor: MilanacColors.red,
              onPressed: () async {
                final current = seasons.value
                    ?.where((s) => s.id == _seasonId)
                    .firstOrNull;
                final savedSeason = await showTrophyEditor(
                  context,
                  seasonLabel: current?.label,
                );
                if (savedSeason != null) {
                  setState(() => _seasonId = savedSeason);
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Aggiungi trofeo'),
            )
          : null,
      body: seasons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore nel caricamento: $e')),
        data: (list) {
          if (list.isEmpty) {
            return _Scene(
              trophies: const [],
              tilt: _tilt,
              header: const _Header(seasons: [], selected: null),
            );
          }
          final current = currentSeasonLabel();
          final selected =
              list.where((s) => s.id == _seasonId).firstOrNull ??
              list.where((s) => s.label == current).firstOrNull ??
              list.first;
          final trophies = ref.watch(trophiesProvider(selected.id));
          return _Scene(
            tilt: _tilt,
            trophies: trophies.value ?? const [],
            loading: trophies.isLoading,
            canEdit: isDirettivo,
            header: _Header(
              seasons: list,
              selected: selected,
              onChanged: (s) => setState(() => _seasonId = s.id),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.seasons,
    required this.selected,
    this.onChanged,
  });
  final List<Season> seasons;
  final Season? selected;
  final ValueChanged<Season>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: MilanacColors.gold),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'LA NOSTRA BACHECA',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4),
            ),
          ),
          if (selected != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: MilanacColors.gold),
                borderRadius: BorderRadius.circular(20),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Season>(
                  value: selected,
                  icon: const Icon(
                    Icons.expand_more_rounded,
                    color: MilanacColors.gold,
                  ),
                  style: const TextStyle(
                    color: MilanacColors.gold,
                    fontWeight: FontWeight.w800,
                  ),
                  dropdownColor: MilanacColors.surfaceHigh,
                  items: [
                    for (final s in seasons)
                      DropdownMenuItem(
                        value: s,
                        child: Text('Stagione ${s.label}'),
                      ),
                  ],
                  onChanged: (s) => s == null ? null : onChanged?.call(s),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Scene extends StatelessWidget {
  const _Scene({
    required this.trophies,
    required this.tilt,
    required this.header,
    this.loading = false,
    this.canEdit = false,
  });

  final List<Trophy> trophies;
  final Offset tilt;
  final Widget header;
  final bool loading;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final shelves = max(_minShelves, (trophies.length / _perShelf).ceil());
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        header,
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AspectRatio(
              aspectRatio: sceneAspect,
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = box.biggest;
                  final inner = cabinetInner(size);
                  final shelfH = inner.height / shelves;
                  final slotW = inner.width / _perShelf;
                  return ClipRect(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Livello 1: sala e bacheca (si muove poco).
                        Positioned.fill(
                          child: Transform.translate(
                            offset: tilt * -4,
                            child: CustomPaint(
                              painter: TrophyRoomPainter(shelves: shelves),
                            ),
                          ),
                        ),
                        // Livello 2: i trofei sulle mensole.
                        for (final (i, t) in trophies.indexed)
                          Positioned(
                            left:
                                inner.left +
                                (i % _perShelf) * slotW +
                                slotW * .1 +
                                tilt.dx * -4,
                            top:
                                inner.top +
                                (i ~/ _perShelf) * shelfH +
                                shelfH * .2 +
                                tilt.dy * -4,
                            width: slotW * .8,
                            height: shelfH * .74,
                            child: _TrophyOnShelf(trophy: t, canEdit: canEdit),
                          ),
                        if (!loading && trophies.isEmpty)
                          Positioned(
                            left: inner.left + 12,
                            right: size.width - inner.right + 12,
                            top: inner.top + shelfH * .35,
                            child: const Text(
                              'Bacheca ancora vuota per questa stagione.\nForza MILANAC, riempiamola!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        // Livello 3: il giocatore in primo piano (si muove di più).
                        Positioned(
                          left: size.width * -.02 + tilt.dx * 10,
                          top: size.height * .52 + tilt.dy * 6,
                          width: size.width * .36,
                          height: size.height * .5,
                          child: const IgnorePointer(
                            child: CustomPaint(
                              painter: AdmiringPlayerPainter(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (trophies.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'TROFEI DELLA STAGIONE',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
          ),
          for (final t in trophies)
            ListTile(
              leading: SizedBox(
                width: 36,
                height: 36,
                child: TrophyVisual(trophy: t),
              ),
              title: Text(
                t.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                [
                  if (t.competition != null) t.competition!,
                  if (t.wonOn != null)
                    DateFormat('d MMMM yyyy', 'it').format(t.wonOn!),
                ].join(' · '),
              ),
              onTap: () => showTrophyDetails(context, t, canEdit: canEdit),
            ),
        ],
      ],
    );
  }
}

class _TrophyOnShelf extends StatelessWidget {
  const _TrophyOnShelf({required this.trophy, required this.canEdit});
  final Trophy trophy;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: trophy.name,
      child: GestureDetector(
        onTap: () => showTrophyDetails(context, trophy, canEdit: canEdit),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFE6A8).withValues(alpha: .18),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: TrophyVisual(trophy: trophy),
        ),
      ),
    );
  }
}

/// Immagine caricata dal Direttivo oppure forma disegnata.
class TrophyVisual extends ConsumerWidget {
  const TrophyVisual({super.key, required this.trophy});
  final Trophy trophy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        errorBuilder: (_, _, _) => drawn,
      ),
    );
  }
}
