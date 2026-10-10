import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../chat/chat_repository.dart' show maxReplaySeconds;
import '../chat/voice_player.dart' show formatSeconds;
import '../chat/voice_recorder.dart';
import '../formazione/formation_repository.dart';
import '../formazione/modules.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import '../tattiche/tactics_repository.dart';
import 'board_model.dart';
import 'board_painter.dart';
import 'replay_pages.dart';

/// Strumenti della lavagna (colonna a sinistra).
enum BoardTool {
  giocatore('Giocatore', Icons.person_add_alt_1_rounded),
  fuoco('Fuoco', Icons.local_fire_department_rounded),
  freccia('Freccia', Icons.north_east_rounded);

  const BoardTool(this.label, this.icon);
  final String label;
  final IconData icon;

  String get hint => switch (this) {
    giocatore =>
      'Tocca il campo per aggiungere un giocatore, trascina i gettoni, tieni premuto per toglierne uno.',
    fuoco => 'Tieni premuto e muovi il dito: la heatmap si accumula dove insisti.',
    freccia =>
      'Trascina da un punto all\'altro. Doppio tocco per passare alle frecce tratteggiate.',
  };
}

/// Apre la lavagna a schermo intero (nuova o da uno schema salvato).
Future<void> openBoard(
  BuildContext context, {
  Tactic? tactic,
  bool readOnly = false,
}) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute(
    builder: (_) => BoardPage(tactic: tactic, readOnly: readOnly),
  ),
);

/// Uno schema salvato aperto dal suo indirizzo (`/lavagna/<id>`).
class SavedBoardPage extends ConsumerWidget {
  const SavedBoardPage({super.key, required this.tacticId});
  final String tacticId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final t = ref
        .watch(tacticsProvider)
        .value
        ?.where((x) => x.id == tacticId)
        .firstOrNull;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('LAVAGNA')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return BoardPage(tactic: t, readOnly: !isDirettivo);
  }
}

/// La lavagna tattica: gettoni dei giocatori, pennello heatmap, frecce, annulla,
/// schemi salvati con immagine, registrazione del replay con la voce.
/// Solo il Direttivo disegna; gli altri guardano gli schemi salvati.
class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({super.key, this.tactic, this.readOnly = false});
  final Tactic? tactic;
  final bool readOnly;

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  late final BoardEditor _editor = BoardEditor(
    widget.tactic?.board ?? const BoardState(),
  );
  BoardTool _tool = BoardTool.giocatore;
  bool _dashed = false;
  String? _dragId;
  String? _selectedId;
  (double, double)? _arrowStart;
  (double, double)? _lastHeat;
  BoardArrow? _pending;
  Size _size = Size.zero;
  int _seq = 0;
  bool _saving = false;

  // Registrazione del replay.
  final _mic = VoiceRecorder();
  ReplayRecorder? _recorder;
  Timer? _timer;
  int _seconds = 0;

  bool get _recording => _recorder != null;

  @override
  void initState() {
    super.initState();
    _editor.addListener(_onChanged);
    if (widget.tactic == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _startFromModule(defaultModule, Team.milanac),
      );
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mic.dispose();
    _editor.removeListener(_onChanged);
    _editor.dispose();
    super.dispose();
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  /// Lavagna nuova dal modulo: i gettoni ai posti del modulo con i giocatori della
  /// formazione della squadra (dove manca il giocatore resta la sigla del ruolo).
  Future<void> _startFromModule(String module, Team team) async {
    var rosa = ref.read(rosaProvider).value ?? const <Member>[];
    if (rosa.isEmpty) {
      try {
        rosa = await ref.read(rosaProvider.future);
      } catch (_) {}
    }
    Formation? formation;
    try {
      formation = await ref.read(formationProvider(team).future);
    } catch (_) {}
    final players = formation != null && formation.module == module
        ? formation.players
        : const <int, String>{};
    final slots = formationModules[module] ?? formationModules[defaultModule]!;
    final tokens = [
      for (final (i, slot) in slots.indexed)
        () {
          final m = rosa.where((x) => x.id == players[i]).firstOrNull;
          return BoardToken(
            id: 'f$i',
            x: slot.x,
            y: slot.y,
            playerId: m?.id,
            label: m?.shirtNumber?.toString() ?? slot.label,
            name: m?.displayName ?? '',
            side: team.name,
          );
        }(),
    ];
    if (!mounted) return;
    final state = BoardState(module: module, team: team.name, tokens: tokens);
    _recording ? _editor.apply(Reset(state)) : _editor.load(state);
  }

  // ---------------------------------------------------------------- gesti

  (double, double) _field(Offset local) => BoardPainter.toField(_size, local);

  BoardToken? _hit(Offset local) {
    var best = BoardPainter.tokenRadius(_size) * 1.4;
    BoardToken? found;
    for (final t in _editor.state.tokens) {
      final d = (BoardPainter.toPixel(_size, t.x, t.y) - local).distance;
      if (d < best) {
        best = d;
        found = t;
      }
    }
    return found;
  }

  void _onTapUp(TapUpDetails d) {
    final hit = _hit(d.localPosition);
    final (x, y) = _field(d.localPosition);
    switch (_tool) {
      case BoardTool.giocatore:
        if (hit != null) {
          setState(() => _selectedId = _selectedId == hit.id ? null : hit.id);
        } else {
          _addPlayer(x, y);
        }
      case BoardTool.fuoco:
        _editor
          ..apply(const HeatStart())
          ..apply(Heat(x, y))
          ..apply(const HeatEnd());
      case BoardTool.freccia:
        break;
    }
  }

  void _onPanStart(DragStartDetails d) {
    final (x, y) = _field(d.localPosition);
    switch (_tool) {
      case BoardTool.giocatore:
        final hit = _hit(d.localPosition);
        if (hit != null) {
          _dragId = hit.id;
          _selectedId = hit.id;
          _editor.apply(DragStart(hit.id));
        }
      case BoardTool.fuoco:
        _lastHeat = (x, y);
        _editor
          ..apply(const HeatStart())
          ..apply(Heat(x, y));
      case BoardTool.freccia:
        _arrowStart = (x, y);
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final (x, y) = _field(d.localPosition);
    switch (_tool) {
      case BoardTool.giocatore:
        if (_dragId != null) _editor.apply(MoveToken(_dragId!, x, y));
      case BoardTool.fuoco:
        final last = _lastHeat;
        if (last == null || (x - last.$1).abs() + (y - last.$2).abs() > .012) {
          _lastHeat = (x, y);
          _editor.apply(Heat(x, y));
        }
      case BoardTool.freccia:
        final s = _arrowStart;
        if (s != null) {
          setState(
            () => _pending = BoardArrow(
              x1: s.$1,
              y1: s.$2,
              x2: x,
              y2: y,
              dashed: _dashed,
            ),
          );
        }
    }
  }

  void _onPanEnd(DragEndDetails d) {
    switch (_tool) {
      case BoardTool.giocatore:
        if (_dragId != null) {
          _editor.apply(const DragEnd());
          _dragId = null;
        }
      case BoardTool.fuoco:
        _lastHeat = null;
        _editor.apply(const HeatEnd());
      case BoardTool.freccia:
        final p = _pending;
        _arrowStart = null;
        setState(() => _pending = null);
        if (p != null && (p.x2 - p.x1).abs() + (p.y2 - p.y1).abs() > .03) {
          _editor.apply(AddArrow(p));
        }
    }
  }

  void _onDoubleTap() {
    if (_tool != BoardTool.freccia) return;
    setState(() => _dashed = !_dashed);
    _notice(_dashed ? 'Frecce tratteggiate.' : 'Frecce continue.');
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (_tool != BoardTool.giocatore) return;
    final hit = _hit(d.localPosition);
    if (hit == null) return;
    HapticFeedback.mediumImpact();
    _editor.apply(RemoveToken(hit.id));
  }

  // ---------------------------------------------------------------- azioni

  Future<void> _addPlayer(double x, double y) async {
    final onBoard = {
      for (final t in _editor.state.tokens)
        if (t.playerId != null) t.playerId!,
    };
    final picked = await showModalBottomSheet<BoardToken>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PlayerSheet(
        onBoard: onBoard,
        team: Team.parse(_editor.state.team) ?? Team.milanac,
      ),
    );
    if (picked == null || !mounted) return;
    _editor.apply(
      AddToken(
        BoardToken(
          id: 'u${DateTime.now().microsecondsSinceEpoch}_${++_seq}',
          x: x,
          y: y,
          playerId: picked.playerId,
          label: picked.label,
          name: picked.name,
          side: picked.side,
        ),
      ),
    );
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pulire la lavagna?'),
        content: const Text('Via gettoni, frecce e heatmap (si può annullare).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Pulisci'),
          ),
        ],
      ),
    );
    if (ok == true) _editor.apply(const Clear());
  }

  Future<void> _pickModule() async {
    var team = Team.parse(_editor.state.team) ?? Team.milanac;
    final module = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Nuova lavagna dal modulo (con la formazione della squadra)',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              SegmentedButton<Team>(
                segments: [
                  for (final t in Team.values)
                    ButtonSegment(value: t, label: Text(t.short)),
                ],
                selected: {team},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setSheet(() => team = s.first),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final m in formationModules.keys)
                    ActionChip(
                      label: Text(m),
                      onPressed: () => Navigator.pop(c, m),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (module != null && mounted) await _startFromModule(module, team);
  }

  Future<void> _save() async {
    final info = await showDialog<_SaveInfo>(
      context: context,
      builder: (_) => _SaveDialog(
        title: widget.tactic?.title ?? '',
        module: _editor.state.module,
        description: widget.tactic?.description ?? '',
      ),
    );
    if (info == null || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final state = _editor.state.copyWith(module: info.module);
      final png = await renderBoardImage(state, width: 900);
      await ref
          .read(tacticsRepositoryProvider)
          .save(
            Tactic(
              id: widget.tactic?.id ?? '',
              title: info.title,
              module: info.module,
              description: info.description,
              imagePath: widget.tactic?.imagePath,
              localImage: widget.tactic?.localImage,
              board: state,
              team: state.team,
            ),
            image: png,
            imageContentType: 'image/png',
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Schema "${info.title}" salvato in Tattiche e schemi.'),
        ),
      );
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Salvataggio non riuscito: $e')),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startRecording() async {
    final ok = await _mic.start();
    if (!ok) {
      _notice(
        kIsWeb
            ? 'La registrazione funziona dall\'app sul telefono.'
            : 'Serve il permesso del microfono per registrare il replay.',
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _recorder = ReplayRecorder(_editor.state);
      _seconds = 0;
    });
    _editor.onCommand = _recorder!.record;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= maxReplaySeconds) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    final rec = _recorder;
    if (rec == null) return;
    _timer?.cancel();
    _editor.onCommand = null;
    setState(() => _recorder = null);
    final audio = await _mic.stop(maxSeconds: maxReplaySeconds, keepFile: true);
    final data = rec.finish(audio == null ? null : audio.seconds * 1000);
    if (!mounted) return;
    if (data.durationMs < 1000) {
      _notice('Registrazione troppo breve.');
      return;
    }
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReplayPreviewPage(
          data: data,
          title: widget.tactic?.title ?? 'Schema',
          audioBytes: audio?.bytes,
          audioPath: audio?.path,
          seconds: audio?.seconds,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- vista

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final readOnly = widget.readOnly || !isDirettivo;
    final state = _editor.state;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tactic?.title.toUpperCase() ?? 'LAVAGNA'),
        actions: [
          if (!readOnly) ...[
            if (_recording)
              _RecordingBadge(seconds: _seconds, onStop: _stopRecording)
            else
              IconButton(
                tooltip: 'Registra il replay',
                icon: const Icon(Icons.mic_rounded, color: MilanacColors.gold),
                onPressed: _startRecording,
              ),
            IconButton(
              tooltip: 'Salva lo schema',
              icon: const Icon(Icons.save_rounded),
              onPressed: _saving ? null : _save,
            ),
            PopupMenuButton<String>(
              tooltip: 'Altro',
              onSelected: (v) {
                if (v == 'modulo') _pickModule();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'modulo',
                  child: Text('Nuova lavagna dal modulo…'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                if (!readOnly)
                  _ToolBar(
                    tool: _tool,
                    dashed: _dashed,
                    canUndo: _editor.canUndo,
                    onTool: (t) => setState(() => _tool = t),
                    onUndo: () => _editor.apply(const Undo()),
                    onClear: _clear,
                  ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AspectRatio(
                        aspectRatio: boardAspect,
                        child: LayoutBuilder(
                          builder: (context, c) {
                            _size = c.biggest;
                            final paint = CustomPaint(
                              key: const ValueKey('lavagna'),
                              painter: BoardPainter(
                                state,
                                pendingArrow: _pending,
                                selectedId: _selectedId,
                              ),
                            );
                            if (readOnly) return paint;
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: _onTapUp,
                              onDoubleTap: _tool == BoardTool.freccia
                                  ? _onDoubleTap
                                  : null,
                              onLongPressStart: _onLongPressStart,
                              onPanStart: _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: _onPanEnd,
                              child: paint,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text(
                readOnly
                    ? 'Solo il Direttivo disegna sulla lavagna.'
                    : _recording
                    ? 'Registrazione in corso: parla e muovi i gettoni, poi ferma.'
                    : _tool.hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Colonna degli strumenti: Giocatore, Fuoco, Freccia, poi Annulla e Pulisci.
class _ToolBar extends StatelessWidget {
  const _ToolBar({
    required this.tool,
    required this.dashed,
    required this.canUndo,
    required this.onTool,
    required this.onUndo,
    required this.onClear,
  });
  final BoardTool tool;
  final bool dashed;
  final bool canUndo;
  final ValueChanged<BoardTool> onTool;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Container(
    width: 68,
    color: MilanacColors.surface,
    child: SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 6),
          for (final t in BoardTool.values)
            _ToolButton(
              icon: t.icon,
              label: t == BoardTool.freccia && dashed ? 'Tratteggio' : t.label,
              selected: t == tool,
              onTap: () => onTool(t),
            ),
          const Divider(height: 12, indent: 12, endIndent: 12),
          _ToolButton(
            icon: Icons.undo_rounded,
            label: 'Annulla',
            enabled: canUndo,
            onTap: onUndo,
          ),
          _ToolButton(
            icon: Icons.cleaning_services_rounded,
            label: 'Pulisci',
            onTap: onClear,
          ),
        ],
      ),
    ),
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? MilanacColors.red : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: !enabled
                  ? Colors.white24
                  : selected
                  ? Colors.white
                  : Colors.white70,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: !enabled
                    ? Colors.white24
                    : selected
                    ? Colors.white
                    : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// In alto durante la registrazione: punto rosso, durata e stop.
class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge({required this.seconds, required this.onStop});
  final int seconds;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.circle, size: 10, color: MilanacColors.red),
      const SizedBox(width: 4),
      Text(
        formatSeconds(seconds),
        style: const TextStyle(fontFamily: sportFont, fontSize: 16),
      ),
      IconButton(
        tooltip: 'Ferma la registrazione',
        icon: const Icon(Icons.stop_circle_rounded, color: MilanacColors.red),
        onPressed: onStop,
      ),
    ],
  );
}

/// Scelta del giocatore da mettere sul campo (o un avversario, o un gettone vuoto).
class _PlayerSheet extends ConsumerStatefulWidget {
  const _PlayerSheet({required this.onBoard, required this.team});
  final Set<String> onBoard;
  final Team team;

  @override
  ConsumerState<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<_PlayerSheet> {
  late Team _team = widget.team;

  @override
  Widget build(BuildContext context) {
    final members =
        (ref.watch(rosaProvider).value ?? const <Member>[])
            .where(
              (m) =>
                  m.active &&
                  m.role != ClubRole.pending &&
                  m.teams.contains(_team) &&
                  !widget.onBoard.contains(m.id),
            )
            .toList()
          ..sort((a, b) => (a.shirtNumber ?? 99).compareTo(b.shirtNumber ?? 99));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<Team>(
              segments: [
                for (final t in Team.values)
                  ButtonSegment(value: t, label: Text(t.short)),
              ],
              selected: {_team},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _team = s.first),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in members)
                    ListTile(
                      leading: MemberAvatar(member: m, radius: 18),
                      title: Text(m.displayName),
                      subtitle: Text(
                        [
                          if (m.fieldPosition != null) m.fieldPosition!,
                          if (m.shirtNumber != null) '#${m.shirtNumber}',
                        ].join(' · '),
                      ),
                      onTap: () => Navigator.pop(
                        context,
                        BoardToken(
                          id: '',
                          x: 0,
                          y: 0,
                          playerId: m.id,
                          label: m.shirtNumber?.toString() ??
                              (m.fieldPosition ?? '?'),
                          name: m.displayName,
                          side: _team.name,
                        ),
                      ),
                    ),
                  if (members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Tutti i giocatori della squadra sono già in campo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  const Divider(),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFF5F5F5),
                      child: Text(
                        'A',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    title: const Text('Avversario'),
                    onTap: () => Navigator.pop(
                      context,
                      const BoardToken(
                        id: '',
                        x: 0,
                        y: 0,
                        label: 'A',
                        side: 'avversari',
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: MilanacColors.red,
                      child: Text('?', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    title: const Text('Gettone senza nome'),
                    onTap: () => Navigator.pop(
                      context,
                      BoardToken(
                        id: '',
                        x: 0,
                        y: 0,
                        label: '?',
                        side: _team.name,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveInfo {
  const _SaveInfo(this.title, this.module, this.description);
  final String title;
  final String module;
  final String description;
}

/// Nome, modulo e spiegazione dello schema da salvare.
class _SaveDialog extends StatefulWidget {
  const _SaveDialog({
    required this.title,
    required this.module,
    required this.description,
  });
  final String title;
  final String module;
  final String description;

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  static const _otherModules = ['Piazzati', 'Difesa', 'Attacco'];
  late final _title = TextEditingController(text: widget.title);
  late final _description = TextEditingController(text: widget.description);
  late String _module = widget.module;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modules = {...formationModules.keys, ..._otherModules, _module}.toList();
    return AlertDialog(
      title: const Text('Salva lo schema'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'es. Uscita dal basso',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _module,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Modulo di partenza'),
              items: [
                for (final m in modules)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => setState(() => _module = v ?? _module),
            ),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Spiegazione (facoltativa)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(
              context,
              _SaveInfo(title, _module, _description.text.trim()),
            );
          },
          child: const Text('Salva'),
        ),
      ],
    );
  }
}
