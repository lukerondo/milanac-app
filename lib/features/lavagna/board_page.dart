import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio_focus.dart';
import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/haptics.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/member_photo.dart';
import '../../shared/ui.dart';
import '../chat/chat_repository.dart' show maxReplaySeconds;
import '../chat/voice_player.dart' show formatSeconds;
import '../chat/voice_recorder.dart';
import '../formazione/formation_repository.dart';
import '../formazione/modules.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import '../tattiche/tactics_repository.dart';
import 'board_model.dart';
import 'board_overlays.dart';
import 'board_painter.dart';
import 'full_page.dart';
import 'replay_pages.dart';
import 'replay_player.dart';
import 'set_pieces.dart';

/// Strumenti della lavagna (barra in basso).
enum BoardTool {
  giocatore('Gettoni', Icons.adjust_rounded),
  pallone('Pallone', Icons.sports_soccer_rounded),
  fuoco('Fuoco', Icons.local_fire_department_rounded),
  freccia('Freccia', Icons.north_east_rounded);

  const BoardTool(this.label, this.icon);
  final String label;
  final IconData icon;

  String get hint => switch (this) {
    giocatore =>
      'Trascina i gettoni. Oro: noi · nero: avversari.\n'
          'Tocca per aggiungere, tieni premuto per togliere.',
    pallone =>
      'Tocca un compagno per passargli la palla, l\'erba per giocarla nello '
          'spazio, la porta per tirare. Trascina il pallone per spostarlo o '
          'darlo a un giocatore.',
    fuoco =>
      'Tieni premuto e muovi il dito: la heatmap si accumula dove insisti.',
    freccia => 'Trascina da un punto all\'altro. Doppio tocco per le frecce tratteggiate.',
  };
}

/// "Pallone" quando il pallone non è in campo (uno schema di prima o tolto): il primo
/// tocco lo mette.
const _placeBallHint =
    'Tocca il campo per mettere il pallone, o un gettone per darglielo.';

/// Chi guarda soltanto: i colori e le linee.
const _readOnlyHint =
    'Oro: noi · nero: avversari. Palla: linea continua il passaggio, ondulata '
    'la conduzione, spessa il tiro, a puntini il cross.\nSolo il Direttivo '
    'disegna sulla lavagna.';

/// Chi guarda uno schema con le posizioni per zona: può spostare solo il pallone.
const _ballOnlyHint =
    'Sposta il pallone: vedi dove devi stare quando la palla è in quella zona.';

/// "Pallone" con le zone di battuta accese: la legenda dei numeri.
String get _crossHint =>
    'Tocca una zona per il cross: $deliveryZoneLegend. Un compagno per '
    'passargli la palla, la porta per tirare.';

/// "Posizioni per zona" (Direttivo): la zona del pallone e come si usa.
String _positionsHint(int? zone, {required bool saved}) => zone == null
    ? 'Posizioni per zona: metti il pallone in campo, sistema i giocatori e '
          'salva le posizioni della sua zona.'
    : '${ballZoneName(zone)} · ${saved ? 'salvata' : 'da salvare'}. Sistema i '
          'giocatori e salva: quando il pallone entra in una zona salvata, '
          'vanno lì da soli.';

/// Nome breve della squadra sulla lavagna.
String _teamName(Team team) => team == Team.milanac ? 'MILANAC' : 'Futuro';

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
          const IconTile(Icons.search_off_rounded, size: 56),
          const SizedBox(height: 14),
          const Text(
            'Schema non trovato',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Forse è stato eliminato.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: context.pal.textMuted),
          ),
          const SizedBox(height: 18),
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
      appBar: fullPageBar(
        context,
        title: 'LAVAGNA',
        onBack: () => _leave(context),
      ),
      body: AsyncView(
        value: tactics,
        onRetry: () => ref.invalidate(tacticsProvider),
        data: (_) => const TacticNotFound(),
      ),
    );
  }
}

/// I gettoni ai posti del modulo con i giocatori della formazione della squadra
/// (dove manca il giocatore resta la sigla del ruolo) e il pallone a centrocampo.
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
    ball: BoardBall.kickOff,
  );
}

Future<void> _quietly(Future<void> f) async {
  try {
    await f;
  } catch (_) {}
}

/// La lavagna tattica: gettoni dei giocatori, pallone con passaggi, conduzioni e
/// tiri, pennello heatmap, frecce, annulla, schemi salvati con immagine,
/// registrazione del replay con la voce.
/// Solo il Direttivo disegna; gli altri guardano gli schemi salvati.
class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({super.key, this.tactic, this.readOnly = false});
  final Tactic? tactic;
  final bool readOnly;

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

/// Quello che la pagina mostra della lavagna, fuori dal campo: "Annulla", modulo e
/// squadra in alto, i suggerimenti (pallone, zone di battuta) e la barra delle
/// posizioni per zona.
typedef _Shown = ({
  bool canUndo,
  String module,
  String team,
  bool hasBall,
  bool zones,
  bool positionsMode,
  bool hasPositions,
  int? ballZone,
  bool zoneSaved,
});

class _BoardPageState extends ConsumerState<BoardPage>
    with TickerProviderStateMixin {
  late final BoardEditor _editor;
  late final AudioFocus _focus;
  BoardTool _tool = BoardTool.giocatore;
  bool _dashed = false;
  String? _dragId;
  String? _selectedId;
  (double, double)? _arrowStart;
  (double, double)? _lastHeat;

  /// Si sta trascinando il pallone.
  bool _ballDrag = false;

  /// Il gettone che prenderebbe il pallone lasciato lì (anello bianco mentre lo si
  /// trascina): la segue solo la lavagna.
  final _target = ValueNotifier<String?>(null);

  /// Il volo del pallone dopo un passaggio o un tiro: solo disegno (lo stato è già
  /// quello d'arrivo), rifatto uguale nel replay.
  final _flight = ValueNotifier<BallFlight?>(null);
  late final AnimationController _flightClock;
  BallKick? _flying;

  /// I giocatori che scivolano verso le posizioni della nuova zona: anche questo solo
  /// disegno, rifatto uguale nel replay.
  final _shift = ValueNotifier<ShiftFrame?>(null);
  late final AnimationController _shiftClock;
  TokenShift? _shifting;

  /// La pennellata in corso ha già messo almeno un punto (e il suo punto di
  /// annullamento).
  bool _heatStroke = false;
  bool _heatFullNoticed = false;

  /// Freccia in corso di disegno: la segue solo la lavagna, non tutta la pagina.
  final _pending = ValueNotifier<BoardArrow?>(null);
  Size _size = Size.zero;
  int _seq = 0;
  bool _saving = false;

  /// Quello che la pagina mostra della lavagna com'era all'ultima costruzione.
  _Shown? _shown;

  _Shown get _visible {
    final s = _editor.state;
    final ball = s.ball;
    final zone = ball == null ? null : ballZoneAt(ball.x, ball.y);
    return (
      canUndo: _editor.canUndo,
      module: s.module,
      team: s.team,
      hasBall: ball != null,
      zones: s.shows(BoardOverlay.zones),
      positionsMode: s.shows(BoardOverlay.zonePositions),
      hasPositions: s.positions.isNotEmpty,
      ballZone: zone,
      zoneSaved: zone != null && s.positions.containsKey(zone),
    );
  }

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
    _flightClock = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: ballFlightMs),
    )..addListener(_onFlight);
    _shiftClock = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: zoneShiftMs),
    )..addListener(_onShift);
    final tactic = widget.tactic;
    if (tactic != null) {
      var board = tactic.board ?? const BoardState();
      // Chi guarda uno schema con le posizioni per zona le vede seguire il pallone
      // che sposta (solo qui: lo schema salvato non cambia).
      if (widget.readOnly &&
          board.positions.isNotEmpty &&
          !board.shows(BoardOverlay.zonePositions)) {
        board = board.copyWith(
          view: {...board.view, BoardOverlay.zonePositions.key: true},
        );
      }
      _editor = BoardEditor(board);
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
  /// quando cambia quello che mostra fuori dal campo ([_visible]). Un passaggio o un
  /// tiro nuovo fa partire il volo del pallone; un cambio di zona con le posizioni
  /// salvate, lo scivolamento dei giocatori.
  void _onChanged() {
    final kick = _editor.lastKick;
    if (!identical(kick, _flying)) {
      _flying = kick;
      if (kick == null) {
        _flightClock.stop();
        _flight.value = null;
      } else {
        _flightClock.forward(from: 0);
      }
    }
    final shift = _editor.lastShift;
    if (!identical(shift, _shifting)) {
      _shifting = shift;
      if (shift == null) {
        _shiftClock.stop();
        _shift.value = null;
      } else {
        _shiftClock.forward(from: 0);
      }
    }
    if (mounted && _visible != _shown) setState(() {});
  }

  void _onFlight() {
    final kick = _flying;
    final t = _flightClock.value;
    _flight.value = kick == null || t >= 1 ? null : BallFlight(kick, t);
  }

  void _onShift() {
    final shift = _shifting;
    final t = _shiftClock.value;
    _shift.value = shift == null || t >= 1 ? null : ShiftFrame(shift, t);
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
    _flightClock.dispose();
    _flight.dispose();
    _shiftClock.dispose();
    _shift.dispose();
    _target.dispose();
    super.dispose();
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  /// Rosa e formazione della squadra, dalla rete se non sono ancora in memoria
  /// (senza rete, dopo qualche secondo restano le sigle dei ruoli).
  Future<(List<Member>, Formation?)> _loadTeam(Team team) async {
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
    return (rosa, formation);
  }

  Future<BoardState> _loadModule(String module, Team team) async {
    final (rosa, formation) = await _loadTeam(team);
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

  /// Uno schema da palla inattiva: come una lavagna dal modulo (si annulla, finisce
  /// nel replay), con i battitori della formazione pubblicata.
  Future<void> _startFromSetPiece(SetPieceTemplate template, Team team) async {
    final (rosa, formation) = await _loadTeam(team);
    if (!mounted) return;
    _editor.apply(Reset(setPieceBoard(template, team, rosa, formation)));
  }

  // ---------------------------------------------------------------- gesti

  (double, double) _field(Offset local) => BoardPainter.toField(_size, local);

  /// Il gettone sotto il dito: il più vicino entro [reach] raggi (di serie si prende
  /// anche toccando poco fuori, bersaglio di almeno 44 px).
  BoardToken? _hit(Offset local, {double reach = 1.6}) {
    var best = BoardPainter.tokenRadius(_size) * reach;
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

  /// Il pallone sotto il dito: toccato in pieno, oppure vicino (almeno 22 dp) ma
  /// fuori dai gettoni. Al piede di un giocatore si prende il pallone toccandolo, il
  /// resto del gettone muove il giocatore.
  bool _onBall(Offset local) {
    final ball = _editor.state.ball;
    if (ball == null) return false;
    final d = (BoardPainter.toPixel(_size, ball.x, ball.y) - local).distance;
    final br = BoardPainter.ballRadius(_size);
    if (d <= max(br * 1.3, 10.0)) return true;
    if (d > max(22.0, br * 2.5)) return false;
    final r = BoardPainter.tokenRadius(_size);
    return !_editor.state.tokens.any(
      (t) => (BoardPainter.toPixel(_size, t.x, t.y) - local).distance <= r,
    );
  }

  /// Il gettone che prende il pallone lasciato in [local] (solo da vicino).
  BoardToken? _receiver(Offset local) => _hit(local, reach: 1.3);

  /// Il punto in porta di un tiro, se il tocco è sulla porta o lì accanto (in alto
  /// la porta avversaria, in basso la nostra): il pallone finisce tra i pali.
  (double, double)? _goalAt(Offset local) {
    final f = BoardPainter.fieldRect(_size);
    final r = BoardPainter.tokenRadius(_size);
    final half = BoardPainter.goalWidth(_size) / 2;
    if ((local.dx - f.center.dx).abs() > half + r) return null;
    final top = local.dy <= f.top + r * 1.5;
    if (!top && local.dy < f.bottom - r * 1.5) return null;
    final inside = max(0.0, half - BoardPainter.ballRadius(_size));
    final (x, _) = _field(
      Offset(
        local.dx.clamp(f.center.dx - inside, f.center.dx + inside),
        f.center.dy,
      ),
    );
    return (x, top ? 0.0 : 1.0);
  }

  /// La zona di battuta sotto il dito, se le zone si vedono (con qualche dp di
  /// margine: sono piccole).
  DeliveryZone? _zoneAt(Offset local) {
    final s = _editor.state;
    if (!s.shows(BoardOverlay.zones)) return null;
    final f = BoardPainter.fieldRect(_size);
    final (x, y) = _field(local);
    const slack = 6.0;
    return deliveryZoneAt(
      s,
      x,
      y,
      slackX: slack / f.width,
      slackY: slack / f.height,
    );
  }

  /// Pallone: un tocco su un gettone gli passa la palla, sulla porta tira, su una
  /// zona di battuta crossa lì, sull'erba la gioca nello spazio (anche da palla
  /// libera, da dov'è). Senza pallone in campo il tocco lo mette.
  void _ballTap(Offset local) {
    final ball = _editor.state.ball;
    final (x, y) = _field(local);
    if (ball == null) {
      final t = _hit(local);
      _editor.apply(
        PlaceBall(t != null ? ballAtFeet(t) : BoardBall(x: x, y: y)),
      );
      return;
    }
    if (_onBall(local)) return;
    final goal = _goalAt(local);
    // Su una zona di battuta il cross, a meno che il dito non sia proprio su un
    // compagno: a lui il passaggio.
    final zone = goal == null ? _zoneAt(local) : null;
    if (zone != null) {
      final mate = _hit(local, reach: 1.1);
      if (mate != null && mate.side != 'avversari') {
        if (mate.id == ball.holder) return;
        Haptics.light();
        _editor.apply(KickBall(x: mate.x, y: mate.y, to: mate.id));
      } else {
        Haptics.light();
        _editor.apply(KickBall(x: zone.x, y: zone.y, cross: true));
      }
      return;
    }
    // Un gettone toccato in pieno vince sulla porta (il portiere sulla linea),
    // la porta sul gettone solo sfiorato.
    final t = _hit(local, reach: 1.1) ?? (goal == null ? _hit(local) : null);
    if (t != null) {
      if (t.id == ball.holder) return;
      Haptics.light();
      _editor.apply(KickBall(x: t.x, y: t.y, to: t.id));
    } else if (goal != null) {
      Haptics.medium();
      _editor.apply(KickBall(x: goal.$1, y: goal.$2, shot: true));
    } else {
      _editor.apply(KickBall(x: x, y: y));
    }
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
    final (x, y) = _field(d.localPosition);
    switch (_tool) {
      case BoardTool.giocatore:
        // Il pallone non si seleziona e non apre la scelta del gettone.
        if (_onBall(d.localPosition)) return;
        final hit = _hit(d.localPosition);
        if (hit != null) {
          setState(() => _selectedId = _selectedId == hit.id ? null : hit.id);
        } else {
          _addPlayer(x, y);
        }
      case BoardTool.pallone:
        _ballTap(d.localPosition);
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
      case BoardTool.giocatore || BoardTool.pallone:
        // Prima il pallone (anche al piede di un giocatore), poi i gettoni: chi ha
        // la palla al piede la porta con sé.
        if (_onBall(d.localPosition)) {
          _ballDrag = true;
          _editor.apply(const GrabBall());
          return;
        }
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

  /// Chi guarda uno schema con le posizioni per zona prende solo il pallone (i
  /// giocatori si mettono da soli).
  void _onBallOnlyPanStart(DragStartDetails d) {
    if (!_onBall(d.localPosition)) return;
    _ballDrag = true;
    _editor.apply(const GrabBall());
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final (x, y) = _field(d.localPosition);
    switch (_tool) {
      case BoardTool.giocatore || BoardTool.pallone:
        if (_ballDrag) {
          _editor.apply(MoveBall(x, y));
          _target.value = _receiver(d.localPosition)?.id;
        } else if (_dragId != null) {
          _editor.apply(MoveToken(_dragId!, x, y));
        }
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
  /// cambiato strumento). Il pallone lasciato su un gettone gli va al piede.
  void _onPanEnd(DragEndDetails d) {
    if (_ballDrag) {
      _ballDrag = false;
      final to = _target.value;
      _target.value = null;
      if (to != null) Haptics.light();
      _editor.apply(DropBall(to));
    }
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

  /// Tenendo premuto un gettone lo si toglie; il pallone invece non si toglie per
  /// sbaglio: apre le sue opzioni.
  void _onLongPressStart(LongPressStartDetails d) {
    if (_tool != BoardTool.giocatore && _tool != BoardTool.pallone) return;
    if (_onBall(d.localPosition)) {
      _ballOptions();
      return;
    }
    if (_tool != BoardTool.giocatore) return;
    final hit = _hit(d.localPosition);
    if (hit == null) return;
    Haptics.medium();
    _editor.apply(RemoveToken(hit.id));
  }

  // ---------------------------------------------------------------- azioni

  /// Il primo numero libero tra i gettoni degli avversari (1, 2, 3...).
  String _nextOpponentNumber() {
    final used = {
      for (final t in _editor.state.tokens)
        if (t.side == 'avversari') t.label,
    };
    var n = 1;
    while (used.contains('$n')) {
      n++;
    }
    return '$n';
  }

  Future<void> _addPlayer(double x, double y) async {
    final onBoard = {
      for (final t in _editor.state.tokens)
        if (t.playerId != null) t.playerId!,
    };
    final opponent = _nextOpponentNumber();
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PlayerSheet(
        onBoard: onBoard,
        team: Team.parse(_editor.state.team) ?? Team.milanac,
        opponentNumber: opponent,
        offerBall: _editor.state.ball == null,
      ),
    );
    if (!mounted) return;
    if (picked is _BallPick) {
      _editor.apply(PlaceBall(BoardBall(x: x, y: y)));
      return;
    }
    if (picked is! BoardToken) return;
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
    final positions = _editor.state.positions.isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pulire la lavagna?'),
        content: Text(
          positions
              ? 'Via gettoni, frecce, heatmap, linee della palla e posizioni per '
                    'zona; il pallone torna a centrocampo (si può annullare).'
              : 'Via gettoni, frecce, heatmap e linee della palla; il pallone '
                    'torna a centrocampo (si può annullare).',
        ),
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

  /// Le opzioni del pallone (si aprono toccando di nuovo "Pallone" o tenendo premuto
  /// il pallone): l'unico modo di toglierlo, così non sparisce per sbaglio.
  Future<void> _ballOptions() async {
    final s = _editor.state;
    final choice = await showModalBottomSheet<BoardCommand>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: SectionLabel('Pallone'),
              ),
              ListTile(
                leading: const _BallAvatar(),
                title: Text(
                  s.ball == null
                      ? 'Metti il pallone a centrocampo'
                      : 'Rimetti il pallone a centrocampo',
                ),
                onTap: () =>
                    Navigator.pop(c, const PlaceBall(BoardBall.kickOff)),
              ),
              if (s.lines.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.timeline_rounded),
                  title: const Text('Cancella le linee della palla'),
                  subtitle: const Text('La numerazione riparte da 1.'),
                  onTap: () => Navigator.pop(c, const ClearBallLines()),
                ),
              if (s.ball != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Togli il pallone'),
                  onTap: () => Navigator.pop(c, const PlaceBall(null)),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice != null && mounted) _editor.apply(choice);
  }

  /// "Vista": gli interruttori di cosa si disegna sul campo (si salvano con lo schema
  /// e finiscono nel replay). Ne arriveranno altri: il foglio li elenca tutti.
  Future<void> _showView({
    required bool readOnly,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ValueListenableBuilder<BoardState>(
          valueListenable: _editor,
          builder: (c, s, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Vista'),
              const SizedBox(height: 4),
              Text(
                readOnly
                    ? 'Cosa mostrare sul campo.'
                    : 'Cosa mostrare sul campo: si salva con lo schema e si '
                          'vede nel replay.',
                style: TextStyle(fontSize: 14, color: c.pal.textMuted),
              ),
              const SizedBox(height: 6),
              for (final o in BoardOverlay.values)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(o.label),
                  subtitle: Text(o.description),
                  value: s.shows(o),
                  onChanged: (on) => _editor.apply(SetView(o.key, on)),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  /// Modulo e squadra in alto: una lavagna nuova dal modulo, con i giocatori della
  /// formazione della squadra, o uno schema da palla inattiva (si può annullare).
  Future<void> _pickModule() async {
    var team = Team.parse(_editor.state.team) ?? Team.milanac;
    final current = _editor.state.module;
    final piece = _editor.state.piece?.kind;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      // Alto quanto serve (con il testo grande scorre invece di traboccare).
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Nuova lavagna dal modulo'),
                const SizedBox(height: 4),
                Text(
                  'I gettoni partono dalla formazione della squadra.',
                  style: TextStyle(fontSize: 14, color: c.pal.textMuted),
                ),
                const SizedBox(height: 14),
                SegmentedTabs(
                  labels: [for (final t in Team.values) _teamName(t)],
                  selected: team.index,
                  onSelected: (i) => setSheet(() => team = Team.values[i]),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in formationModules.keys)
                      // Larga quanto il suo testo (in una Wrap si allargherebbe).
                      IntrinsicWidth(
                        child: FilterPill(
                          label: m,
                          selected: m == current,
                          onTap: () => Navigator.pop(c, m),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                const SectionLabel('Palle inattive'),
                const SizedBox(height: 4),
                Text(
                  'Pallone sul punto giusto, i giocatori ai loro posti e chi '
                  'batte dalla formazione pubblicata.',
                  style: TextStyle(fontSize: 14, color: c.pal.textMuted),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in SetPieceTemplate.values)
                      IntrinsicWidth(
                        child: FilterPill(
                          label: t.label,
                          selected: current == setPieceModule && t.key == piece,
                          onTap: () => Navigator.pop(c, t),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (picked) {
      case final String module:
        await _startFromModule(module, team);
      case final SetPieceTemplate template:
        await _startFromSetPiece(template, team);
    }
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
    Haptics.medium();
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
            style: dangerButtonStyle(c),
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

  /// Indietro: con la conferma se si sta registrando; aperta da un link (niente
  /// sotto), si torna alle tattiche.
  Future<void> _back() async {
    if (await Navigator.of(context).maybePop()) return;
    if (mounted) context.go('/tattiche');
  }

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
    final shown = _shown = _visible;
    final hasBall = shown.hasBall;
    // Chi guarda uno schema con le posizioni per zona sposta il pallone (e basta).
    final ballOnly = readOnly && shown.hasPositions && hasBall;
    final positionsBar = !readOnly && shown.positionsMode;
    final hint = readOnly
        ? (ballOnly ? _ballOnlyHint : _readOnlyHint)
        : _recording
        ? 'Registrazione in corso: parla, muovi gettoni e pallone, poi ferma.'
        : shown.positionsMode
        ? _positionsHint(shown.ballZone, saved: shown.zoneSaved)
        : _tool == BoardTool.pallone && !hasBall
        ? _placeBallHint
        : _tool == BoardTool.pallone && shown.zones
        ? _crossHint
        : _tool.hint;
    final p = context.pal;
    return PopScope(
      canPop: !_recording && !_micBusy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _recording) _confirmExit();
      },
      child: Scaffold(
        appBar: fullPageBar(
          context,
          title: 'LAVAGNA',
          onBack: _back,
          actions: [
            if (!readOnly)
              AlwaysDark(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_recording)
                      _RecordingButton(
                        seconds: _seconds,
                        onStop: _stopRecording,
                      )
                    else
                      _RecordButton(
                        onPressed: _saving || _micBusy ? null : _startRecording,
                      ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Salva lo schema',
                      child: FilledButton(
                        onPressed: _saving || _recording || _micBusy
                            ? null
                            : _save,
                        style: _headerButtonStyle(FilledButton.styleFrom()),
                        child: const Text('Salva'),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 12),
          ],
          bottom: _BoardInfoBar(
            module: shown.module,
            team: Team.parse(shown.team) ?? Team.milanac,
            title: widget.tactic?.title,
            onTap: readOnly ? null : _pickModule,
            onView: () => _showView(readOnly: readOnly),
          ),
        ),
        // Come nella tavola: il campo subito sotto la barra in alto e il suggerimento
        // sotto il campo; lo spazio che avanza resta in fondo.
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                Flexible(
                  child: AspectRatio(
                    aspectRatio: boardAspect,
                    child: PitchFrame(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          _size = c.biggest;
                          final board = BoardCanvas(
                            key: const ValueKey('lavagna'),
                            board: _editor,
                            pendingArrow: _pending,
                            flight: _flight,
                            shift: _shift,
                            target: _target,
                            selectedId: _selectedId,
                          );
                          if (ballOnly) {
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              dragStartBehavior: DragStartBehavior.down,
                              onPanStart: _onBallOnlyPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: _onPanEnd,
                              child: board,
                            );
                          }
                          if (readOnly) return board;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            // Il trascinamento parte da dove si è appoggiato il
                            // dito: serve per prendere il pallone, che è piccolo.
                            dragStartBehavior: DragStartBehavior.down,
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
                const SizedBox(height: 10),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    color: p.textMuted,
                  ),
                ),
                if (positionsBar) ...[
                  const SizedBox(height: 8),
                  _ZoneBar(
                    zone: shown.ballZone,
                    saved: shown.zoneSaved,
                    onSave: (zone) {
                      Haptics.light();
                      _editor.apply(SaveZone(zone));
                    },
                    onDelete: (zone) => _editor.apply(ClearZone(zone)),
                  ),
                ],
              ],
            ),
          ),
        ),
        // In basso come una barra: gli avvisi compaiono sopra, non coprono gli
        // strumenti.
        bottomNavigationBar: readOnly
            ? null
            : _ToolBar(
                tool: _tool,
                dashed: _dashed,
                canUndo: shown.canUndo,
                onTool: (t) {
                  // "Pallone" toccato di nuovo apre le sue opzioni.
                  if (t == BoardTool.pallone && _tool == t) {
                    _ballOptions();
                  } else {
                    setState(() => _tool = t);
                  }
                },
                onUndo: () => _editor.apply(const Undo()),
                onClear: _clear,
              ),
      ),
    );
  }
}

/// I pulsanti della barra in alto: alti 40, angoli da 10, testo 14 in grassetto.
ButtonStyle _headerButtonStyle(ButtonStyle base) => base.copyWith(
  minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(fontFamily: bodyFont, fontSize: 14, fontWeight: FontWeight.w700),
  ),
);

/// "Registra": bordo oro, il cerchio con il punto rosso.
class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: 'Registra il replay',
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: _headerButtonStyle(
          OutlinedButton.styleFrom(
            foregroundColor: p.accentText,
            disabledForegroundColor: p.textDisabled,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: BorderSide(
              color: onPressed == null ? p.border : p.chipBorder,
              width: 1.5,
            ),
          ),
        ),
        icon: SizedBox.square(
          dimension: 16,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.circle_outlined, size: 16),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: p.danger,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
        label: const Text('Registra'),
      ),
    );
  }
}

/// Durante la registrazione, al posto di "Registra": punto rosso, durata e stop.
class _RecordingButton extends StatelessWidget {
  const _RecordingButton({required this.seconds, required this.onStop});
  final int seconds;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: 'Ferma la registrazione',
      child: OutlinedButton(
        onPressed: onStop,
        style: _headerButtonStyle(
          OutlinedButton.styleFrom(
            foregroundColor: p.text,
            backgroundColor: p.dangerBg,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: BorderSide(color: p.danger, width: 1.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: p.danger),
            const SizedBox(width: 6),
            Text(
              formatSeconds(seconds),
              style: const TextStyle(
                fontFamily: sportFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.stop_rounded, size: 20, color: p.danger),
          ],
        ),
      ),
    );
  }
}

/// Sotto il titolo: modulo, squadra, nome dello schema e "Vista" (sempre su fondo
/// scuro).
class _BoardInfoBar extends StatelessWidget implements PreferredSizeWidget {
  const _BoardInfoBar({
    required this.module,
    required this.team,
    required this.onView,
    this.title,
    this.onTap,
  });
  final String module;
  final Team team;
  final String? title;

  /// Apre la scelta di modulo e squadra (null = solo da guardare).
  final VoidCallback? onTap;

  /// Apre gli interruttori di "Vista".
  final VoidCallback onView;

  @override
  Size get preferredSize => const Size.fromHeight(47);

  @override
  Widget build(BuildContext context) => AlwaysDark(
    child: Builder(
      builder: (context) {
        final p = context.pal;
        return Container(
          height: preferredSize.height,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: Row(
            children: [
              _InfoPill(label: module, onTap: onTap, dropdown: onTap != null),
              const SizedBox(width: 8),
              _InfoPill(label: _teamName(team), onTap: onTap),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 14, color: p.textMuted),
                ),
              ),
              const SizedBox(width: 8),
              _ViewButton(onTap: onView),
            ],
          ),
        );
      },
    ),
  );
}

/// "Posizioni per zona" (Direttivo), sotto il suggerimento: salva dove stanno adesso
/// i gettoni come posizioni per la zona del pallone, o le cancella (si annulla).
class _ZoneBar extends StatelessWidget {
  const _ZoneBar({
    required this.zone,
    required this.saved,
    required this.onSave,
    required this.onDelete,
  });

  /// La zona del pallone (null = pallone non in campo).
  final int? zone;
  final bool saved;
  final ValueChanged<int> onSave;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final z = zone;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: z == null ? null : () => onSave(z),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.push_pin_outlined, size: 18),
            label: const Text(
              'Salva posizioni per questa zona',
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        ),
        if (z != null && saved) ...[
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Cancella le posizioni di questa zona',
            onPressed: () => onDelete(z),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ],
    );
  }
}

/// "Vista": l'occhio tondo in fondo alla barra, alto come le pillole.
class _ViewButton extends StatelessWidget {
  const _ViewButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final shape = CircleBorder(side: BorderSide(color: p.borderStrong));
    return Tooltip(
      message: 'Vista',
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(Icons.visibility_outlined, size: 18, color: p.text),
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, this.onTap, this.dropdown = false});
  final String label;
  final VoidCallback? onTap;
  final bool dropdown;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const shape = StadiumBorder();
    final pill = Container(
      height: 36,
      padding: EdgeInsets.only(left: 12, right: dropdown ? 8 : 12),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: p.borderStrong)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          if (dropdown) ...[
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 18, color: p.text),
          ],
        ],
      ),
    );
    if (onTap == null) return pill;
    return Tooltip(
      message: 'Nuova lavagna dal modulo',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(customBorder: shape, onTap: onTap, child: pill),
      ),
    );
  }
}

/// Barra degli strumenti in basso (sempre scura): Gettoni, Pallone, Fuoco, Freccia,
/// poi Annulla e Pulisci; lo strumento attivo in oro. La freccia tratteggiata si vede
/// dall'icona (l'etichetta resta corta: sei pulsanti stanno anche a 320 dp).
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
  Widget build(BuildContext context) => AlwaysDark(
    child: Builder(
      builder: (context) {
        final p = context.pal;
        final buttons = [
          for (final t in BoardTool.values)
            _ToolButton(
              icon: t == BoardTool.freccia
                  ? _ArrowGlyph(dashed: dashed)
                  : Icon(t.icon),
              label: t.label,
              value: t == BoardTool.freccia
                  ? (dashed ? 'tratteggiata' : 'continua')
                  : null,
              selected: t == tool,
              onTap: () => onTool(t),
            ),
          _ToolButton(
            icon: const Icon(Icons.undo_rounded),
            label: 'Annulla',
            enabled: canUndo,
            onTap: onUndo,
          ),
          _ToolButton(
            icon: const Icon(Icons.delete_outline_rounded),
            label: 'Pulisci',
            onTap: onClear,
          ),
        ];
        return Material(
          color: p.surface,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 10),
              // Sei pulsanti: a 320 dp ognuno è largo 48, quanto basta per
              // "Gettoni" in grassetto.
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  children: [
                    for (final (i, b) in buttons.indexed) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(child: b),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.selected = false,
    this.enabled = true,
  });

  /// L'icona (prende colore e misura dal pulsante).
  final Widget icon;
  final String label;
  final VoidCallback onTap;

  /// Per chi usa il lettore dello schermo (la freccia: continua o tratteggiata).
  final String? value;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final color = !enabled
        ? p.textDisabled
        : selected
        ? p.accentText
        : p.textSecondary;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: selected ? p.accentTintBorder : Colors.transparent,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      value: value,
      child: Material(
        color: selected ? p.accentTint : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: IconThemeData(size: 22, color: color),
                  child: icon,
                ),
                const SizedBox(height: 3),
                // Intera anche nel pulsante più stretto (o con il testo grande):
                // semmai si rimpicciolisce, non si taglia.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: color,
                      ),
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

/// L'icona di "Freccia": la freccia continua o tratteggiata, come quella che si
/// disegnerà.
class _ArrowGlyph extends StatelessWidget {
  const _ArrowGlyph({required this.dashed});
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SizedBox.square(
      dimension: theme.size ?? 24,
      child: CustomPaint(
        painter: _ArrowGlyphPainter(
          dashed: dashed,
          color: theme.color ?? MilanacColors.ivory,
        ),
      ),
    );
  }
}

class _ArrowGlyphPainter extends CustomPainter {
  const _ArrowGlyphPainter({required this.dashed, required this.color});
  final bool dashed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final from = Offset(s * .2, s * .8), tip = Offset(s * .8, s * .2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .1
      ..strokeCap = StrokeCap.round;
    final dir = (tip - from) / (tip - from).distance;
    final end = tip - dir * s * .18;
    if (dashed) {
      // Tre trattini fino alla punta.
      final length = (end - from).distance;
      for (var i = 0; i < 3; i++) {
        final a = from + dir * (length * i / 3);
        final b = from + dir * (length * (i + .55) / 3);
        canvas.drawLine(a, b, paint);
      }
    } else {
      canvas.drawLine(from, end, paint);
    }
    final n = Offset(-dir.dy, dir.dx);
    final head = s * .34;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          tip.dx - dir.dx * head + n.dx * head * .5,
          tip.dy - dir.dy * head + n.dy * head * .5,
        )
        ..lineTo(
          tip.dx - dir.dx * head - n.dx * head * .5,
          tip.dy - dir.dy * head - n.dy * head * .5,
        )
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ArrowGlyphPainter old) =>
      old.dashed != dashed || old.color != color;
}

/// Il pallone grande come un gettone piccolo (nei fogli della lavagna).
class _BallAvatar extends StatelessWidget {
  const _BallAvatar();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: MilanacColors.pitch,
      shape: BoxShape.circle,
    ),
    child: const BallGlyph(size: 30),
  );
}

/// Il pallone scelto nel foglio dei gettoni.
class _BallPick {
  const _BallPick();
}

/// Un gettone piccolo come sulla lavagna (nella scelta del giocatore).
class _TokenAvatar extends StatelessWidget {
  const _TokenAvatar({required this.label, required this.side});
  final String label;
  final String side;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: tokenColor(side),
      shape: BoxShape.circle,
      border: Border.all(color: MilanacColors.ivory, width: 2),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: sportFont,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: tokenTextColor(side),
      ),
    ),
  );
}

/// Scelta del giocatore da mettere sul campo (o un avversario, o un gettone vuoto, o
/// il pallone se non c'è).
class _PlayerSheet extends ConsumerStatefulWidget {
  const _PlayerSheet({
    required this.onBoard,
    required this.team,
    required this.opponentNumber,
    this.offerBall = false,
  });
  final Set<String> onBoard;
  final Team team;

  /// Numero del prossimo avversario.
  final String opponentNumber;

  /// Il pallone non è in campo (schema di prima): lo si può mettere da qui.
  final bool offerBall;

  @override
  ConsumerState<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<_PlayerSheet> {
  late Team _team = widget.team;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
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
          ..sort(
            (a, b) => (a.shirtNumber ?? 99).compareTo(b.shirtNumber ?? 99),
          );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Aggiungi un gettone'),
                  const SizedBox(height: 10),
                  SegmentedTabs(
                    labels: [for (final t in Team.values) _teamName(t)],
                    selected: _team.index,
                    onSelected: (i) => setState(() => _team = Team.values[i]),
                  ),
                ],
              ),
            ),
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
                          label:
                              m.shirtNumber?.toString() ??
                              (m.fieldPosition ?? '?'),
                          name: m.displayName,
                          side: _team.name,
                        ),
                      ),
                    ),
                  if (members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Tutti i giocatori della squadra sono già in campo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: p.textMuted),
                      ),
                    ),
                  const Divider(),
                  ListTile(
                    leading: _TokenAvatar(
                      label: widget.opponentNumber,
                      side: 'avversari',
                    ),
                    title: const Text('Avversario'),
                    onTap: () => Navigator.pop(
                      context,
                      BoardToken(
                        id: '',
                        x: 0,
                        y: 0,
                        label: widget.opponentNumber,
                        side: 'avversari',
                      ),
                    ),
                  ),
                  if (widget.offerBall)
                    ListTile(
                      leading: const _BallAvatar(),
                      title: const Text('Pallone'),
                      onTap: () => Navigator.pop(context, const _BallPick()),
                    ),
                  ListTile(
                    leading: _TokenAvatar(label: '?', side: _team.name),
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
    final modules = {
      ...formationModules.keys,
      ..._otherModules,
      _module,
    }.toList();
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
              decoration: const InputDecoration(
                labelText: 'Modulo di partenza',
              ),
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
