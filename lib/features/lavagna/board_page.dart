import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio_focus.dart';
import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
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
import 'replay_player.dart';

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

/// Il microfono della registrazione del replay (nei test si sostituisce).
final replayMicProvider = Provider<VoiceRecorder Function()>(
  (_) => VoiceRecorder.new,
);

/// Esce dalla pagina: indietro se si può, altrimenti (aperta da un link) alle tattiche.
void _leave(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
  } else {
    context.go('/tattiche');
  }
}

/// Lo schema cercato non c'è (eliminato, o un link vecchio): si torna alle tattiche.
class TacticNotFound extends StatelessWidget {
  const TacticNotFound({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, size: 40, color: Colors.white54),
          const SizedBox(height: 12),
          const Text(
            'Schema non trovato',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Forse è stato eliminato.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _leave(context),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Torna alle tattiche'),
          ),
        ],
      ),
    ),
  );
}

/// Uno schema salvato aperto dal suo indirizzo (`/lavagna/<id>`).
class SavedBoardPage extends ConsumerStatefulWidget {
  const SavedBoardPage({super.key, required this.tacticId});
  final String tacticId;

  @override
  ConsumerState<SavedBoardPage> createState() => _SavedBoardPageState();
}

class _SavedBoardPageState extends ConsumerState<SavedBoardPage> {
  /// Lo schema, una volta arrivato: la lavagna aperta resta anche se nel frattempo
  /// sparisce dall'elenco (salvandolo si viene avvisati che non c'è più).
  Tactic? _tactic;

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final tactics = ref.watch(tacticsProvider);
    final t = _tactic =
        tactics.value?.where((x) => x.id == widget.tacticId).firstOrNull ??
        _tactic;
    if (t != null) return BoardPage(tactic: t, readOnly: !isDirettivo);
    return Scaffold(
      appBar: AppBar(title: const Text('LAVAGNA')),
      body: AsyncView(
        value: tactics,
        onRetry: () => ref.invalidate(tacticsProvider),
        data: (_) => const TacticNotFound(),
      ),
    );
  }
}

/// I gettoni ai posti del modulo con i giocatori della formazione della squadra
/// (dove manca il giocatore resta la sigla del ruolo).
BoardState _moduleBoard(
  String module,
  Team team,
  List<Member> rosa,
  Formation? formation,
) {
  final players = formation != null && formation.module == module
      ? formation.players
      : const <int, String>{};
  final slots = formationModules[module] ?? formationModules[defaultModule]!;
  return BoardState(
    module: module,
    team: team.name,
    tokens: [
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
    ],
  );
}

Future<void> _quietly(Future<void> f) async {
  try {
    await f;
  } catch (_) {}
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
  late final BoardEditor _editor;
  late final AudioFocus _focus;
  BoardTool _tool = BoardTool.giocatore;
  bool _dashed = false;
  String? _dragId;
  String? _selectedId;
  (double, double)? _arrowStart;
  (double, double)? _lastHeat;

  /// La pennellata in corso ha già messo almeno un punto (e il suo punto di
  /// annullamento).
  bool _heatStroke = false;
  bool _heatFullNoticed = false;

  /// Freccia in corso di disegno: la segue solo la lavagna, non tutta la pagina.
  final _pending = ValueNotifier<BoardArrow?>(null);
  Size _size = Size.zero;
  int _seq = 0;
  bool _saving = false;

  /// "Annulla" com'era all'ultima costruzione della pagina.
  bool _shownCanUndo = false;

  // Registrazione del replay.
  late final VoiceRecorder _mic;
  ReplayRecorder? _recorder;
  Timer? _timer;
  int _seconds = 0;

  /// Il microfono si sta aprendo o chiudendo: niente secondo avvio (doppio tocco
  /// su "Registra") né uscita a metà. Chi lo apre o chiude pensa anche a chiuderlo
  /// se intanto la pagina se n'è andata.
  bool _micBusy = false;

  bool get _recording => _recorder != null;

  @override
  void initState() {
    super.initState();
    _focus = ref.read(audioFocusProvider.notifier);
    _mic = ref.read(replayMicProvider)();
    final tactic = widget.tactic;
    if (tactic != null) {
      _editor = BoardEditor(tactic.board ?? const BoardState());
    } else {
      // Lavagna nuova: subito i gettoni del modulo, con i giocatori se rosa e
      // formazione sono già in memoria, altrimenti con le sigle dei ruoli.
      const team = Team.milanac;
      final rosa = ref.read(rosaProvider).value ?? const <Member>[];
      final formation = ref.read(formationProvider(team));
      final board = _moduleBoard(defaultModule, team, rosa, formation.value);
      _editor = BoardEditor(board);
      if (rosa.isEmpty || !formation.hasValue) _fillNewBoard(board);
    }
    _editor.addListener(_onChanged);
  }

  /// La lavagna si ridisegna da sola ([BoardCanvas]): la pagina si ricostruisce solo
  /// quando "Annulla" si accende o si spegne.
  void _onChanged() {
    if (mounted && _editor.canUndo != _shownCanUndo) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _editor.onCommand = null;
    if (_recording || _micBusy) {
      releaseAudioLater(_focus, AudioUse.registrazioneReplay);
    }
    if (!_micBusy) {
      final mic = _mic;
      if (_recording) {
        // Uscita a registrazione in corso: la voce si butta, file compreso.
        unawaited(_quietly(mic.cancel()).whenComplete(mic.dispose));
      } else {
        mic.dispose();
      }
    }
    _editor.removeListener(_onChanged);
    _editor.dispose();
    _pending.dispose();
    super.dispose();
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  /// Rosa e formazione della squadra, dalla rete se non sono ancora in memoria
  /// (senza rete, dopo qualche secondo restano le sigle dei ruoli).
  Future<BoardState> _loadModule(String module, Team team) async {
    const wait = Duration(seconds: 8);
    final cached = ref.read(rosaProvider).value ?? const <Member>[];
    final rosaFuture = cached.isEmpty
        ? ref.read(rosaProvider.future)
        : Future.value(cached);
    final formationFuture = ref.read(formationProvider(team).future);
    var rosa = cached;
    try {
      rosa = await rosaFuture.timeout(wait);
    } catch (_) {}
    Formation? formation;
    try {
      formation = await formationFuture.timeout(wait);
    } catch (_) {}
    return _moduleBoard(module, team, rosa, formation);
  }

  /// I giocatori della lavagna nuova arrivati dalla rete: si mettono solo se nel
  /// frattempo non si è iniziato a disegnare (niente lavoro cancellato).
  Future<void> _fillNewBoard(BoardState first) async {
    final full = await _loadModule(defaultModule, Team.milanac);
    if (!mounted || !identical(_editor.state, first) || _editor.canUndo) return;
    _recording ? _editor.apply(Reset(full)) : _editor.load(full);
  }

  /// "Nuova lavagna dal modulo": si può annullare (e se si sta registrando
  /// finisce nel replay).
  Future<void> _startFromModule(String module, Team team) async {
    final state = await _loadModule(module, team);
    if (!mounted) return;
    _editor.apply(Reset(state));
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

  /// Un punto di heatmap: non dove il colore è già pieno, non oltre il limite
  /// (con un avviso, una volta per pennellata).
  void _heatAt(double x, double y) {
    final s = _editor.state;
    if (s.heatFull) {
      if (!_heatFullNoticed) {
        _heatFullNoticed = true;
        _notice('Heatmap al completo: annulla o pulisci per disegnarne altra.');
      }
      return;
    }
    if (s.heatSaturatedAt(x, y)) return;
    if (!_heatStroke) {
      _heatStroke = true;
      _editor.apply(const HeatStart());
    }
    _editor.apply(Heat(x, y));
  }

  void _endHeat() {
    if (_heatStroke) _editor.apply(const HeatEnd());
    _heatStroke = false;
    _heatFullNoticed = false;
    _lastHeat = null;
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
        _heatAt(x, y);
        _endHeat();
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
          setState(() => _selectedId = hit.id);
          _editor.apply(DragStart(hit.id));
        }
      case BoardTool.fuoco:
        _lastHeat = (x, y);
        _heatAt(x, y);
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
          _heatAt(x, y);
        }
      case BoardTool.freccia:
        final s = _arrowStart;
        if (s != null) {
          _pending.value = BoardArrow(
            x1: s.$1,
            y1: s.$2,
            x2: x,
            y2: y,
            dashed: _dashed,
          );
        }
    }
  }

  /// Fine del gesto: chiude quello che era in corso (anche se nel frattempo si è
  /// cambiato strumento).
  void _onPanEnd(DragEndDetails d) {
    if (_dragId != null) {
      _editor.apply(const DragEnd());
      _dragId = null;
    }
    _endHeat();
    final p = _pending.value;
    _arrowStart = null;
    _pending.value = null;
    if (p != null && (p.x2 - p.x1).abs() + (p.y2 - p.y1).abs() > .03) {
      _editor.apply(AddArrow(p));
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
    // Serve anche se intanto la pagina si chiude.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final state = _editor.state.copyWith(module: info.module);
      final png = await renderBoardImage(state, width: 900);
      await container
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
      // L'elenco si aggiorna anche in tempo reale; per sicurezza si ricarica.
      container.invalidate(tacticsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Schema "${info.title}" salvato in Tattiche e schemi.'),
        ),
      );
      if (mounted) nav.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Salvataggio non riuscito')),
        ),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startRecording() async {
    if (_recording || _micBusy) return; // doppio tocco: una sola registrazione
    setState(() => _micBusy = true);
    // Musica e altri lettori si fermano prima che il microfono si apra.
    _focus.claim(AudioUse.registrazioneReplay);
    var ok = false;
    try {
      ok = await _mic.start();
    } catch (_) {}
    if (!mounted) {
      // Pagina chiusa mentre il microfono si apriva: si butta tutto.
      if (ok) await _quietly(_mic.cancel());
      _mic.dispose();
      return;
    }
    if (!ok) {
      _focus.release(AudioUse.registrazioneReplay);
      setState(() => _micBusy = false);
      _notice(
        kIsWeb
            ? 'La registrazione funziona dall\'app sul telefono.'
            : 'Serve il permesso del microfono per registrare il replay.',
      );
      return;
    }
    HapticFeedback.mediumImpact();
    final recorder = _editor.startRecording();
    setState(() {
      _micBusy = false;
      _seconds = 0;
      _recorder = recorder;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_recording) return;
      setState(() => _seconds++);
      if (_seconds >= maxReplaySeconds) _stopRecording();
    });
  }

  /// Chiude il microfono: la voce registrata, oppure niente (buttata con [discard],
  /// troppo breve, microfono in errore).
  Future<({Uint8List bytes, int seconds, String path})?> _closeMic({
    required bool discard,
  }) async {
    try {
      if (discard) {
        await _mic.cancel(); // via anche il file temporaneo
        return null;
      }
      return await _mic.stop(maxSeconds: maxReplaySeconds, keepFile: true);
    } catch (_) {
      return null;
    }
  }

  Future<void> _stopRecording() async {
    final rec = _recorder;
    if (rec == null || _micBusy) return;
    _timer?.cancel();
    _editor.onCommand = null;
    final durationMs = rec.elapsedMs;
    // Il contatore è ancora a 0:00: troppo breve per un replay.
    final tooShort = _seconds < 1;
    setState(() {
      _recorder = null;
      _micBusy = true;
    });
    final audio = await _closeMic(discard: tooShort);
    _focus.release(AudioUse.registrazioneReplay);
    if (!mounted) {
      final path = audio?.path;
      if (path != null && path.isNotEmpty) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
      _mic.dispose();
      return;
    }
    setState(() => _micBusy = false);
    if (tooShort) {
      _notice('Registrazione troppo breve.');
      return;
    }
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReplayPreviewPage(
          data: rec.finish(durationMs),
          title: widget.tactic?.title ?? 'Schema',
          audioBytes: audio?.bytes,
          audioPath: audio?.path,
          seconds: audio?.seconds,
        ),
      ),
    );
  }

  /// Uscita confermata durante la registrazione: voce e mosse registrate si buttano.
  Future<void> _discardRecording() async {
    if (_recorder == null || _micBusy) return;
    _timer?.cancel();
    _editor.onCommand = null;
    setState(() {
      _recorder = null;
      _micBusy = true;
    });
    await _closeMic(discard: true);
    _focus.release(AudioUse.registrazioneReplay);
    if (!mounted) {
      _mic.dispose();
      return;
    }
    setState(() => _micBusy = false);
  }

  /// Indietro durante la registrazione: il replay si perderebbe, quindi si chiede.
  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Interrompere la registrazione?'),
        content: const Text(
          'Il replay non è ancora stato salvato: uscendo andrà perso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Continua'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || !_recording) return;
    await _discardRecording();
    if (mounted) _leave(context);
  }

  // ---------------------------------------------------------------- vista

  @override
  Widget build(BuildContext context) {
    // Un altro prende l'audio (una chiamata...): la registrazione si ferma lì.
    ref.listen(audioFocusProvider, (_, uses) {
      if (_recording && !uses.contains(AudioUse.registrazioneReplay)) {
        _stopRecording();
      }
    });
    // La rosa serve alla lavagna (giocatori del modulo, scelta del gettone): resta
    // attiva finché la pagina è aperta, altrimenti Riverpod la mette in pausa e i
    // giocatori del modulo non arriverebbero mai.
    ref.watch(rosaProvider);
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final readOnly = widget.readOnly || !isDirettivo;
    final canUndo = _shownCanUndo = _editor.canUndo;
    return PopScope(
      canPop: !_recording && !_micBusy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _recording) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.tactic?.title.toUpperCase() ?? 'LAVAGNA'),
          actions: [
            if (!readOnly) ...[
              if (_recording)
                _RecordingBadge(seconds: _seconds, onStop: _stopRecording)
              else
                IconButton(
                  tooltip: 'Registra il replay',
                  icon: const Icon(
                    Icons.mic_rounded,
                    color: MilanacColors.gold,
                  ),
                  onPressed: _saving || _micBusy ? null : _startRecording,
                ),
              IconButton(
                tooltip: 'Salva lo schema',
                icon: const Icon(Icons.save_rounded),
                onPressed: _saving || _recording || _micBusy ? null : _save,
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
                      canUndo: canUndo,
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
                              final board = BoardCanvas(
                                key: const ValueKey('lavagna'),
                                board: _editor,
                                pendingArrow: _pending,
                                selectedId: _selectedId,
                              );
                              if (readOnly) return board;
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
                                child: board,
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
