import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Gettone di un giocatore sulla lavagna. [x] e [y] vanno da 0 a 1 sul campo
/// (0,0 in alto a sinistra, porta avversaria in alto).
@immutable
class BoardToken {
  const BoardToken({
    required this.id,
    required this.x,
    required this.y,
    this.playerId,
    this.label = '',
    this.name = '',
    this.side = 'milanac',
  });

  final String id;
  final double x;
  final double y;

  /// Membro della rosa (null per un gettone generico o un avversario).
  final String? playerId;

  /// Numero di maglia o sigla dentro il gettone.
  final String label;

  /// Nome sulla carta, sotto il gettone.
  final String name;

  /// milanac · futuro · avversari (colore del gettone).
  final String side;

  BoardToken moved(double x, double y) => BoardToken(
    id: id,
    x: x,
    y: y,
    playerId: playerId,
    label: label,
    name: name,
    side: side,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': _r(x),
    'y': _r(y),
    if (playerId != null) 'p': playerId,
    if (label.isNotEmpty) 'l': label,
    if (name.isNotEmpty) 'n': name,
    if (side != 'milanac') 's': side,
  };

  factory BoardToken.fromJson(Map<String, dynamic> m) => BoardToken(
    id: m['id'] as String,
    x: (m['x'] as num).toDouble(),
    y: (m['y'] as num).toDouble(),
    playerId: m['p'] as String?,
    label: (m['l'] as String?) ?? '',
    name: (m['n'] as String?) ?? '',
    side: (m['s'] as String?) ?? 'milanac',
  );
}

/// Freccia da un punto a un altro (continua o tratteggiata).
@immutable
class BoardArrow {
  const BoardArrow({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.dashed = false,
  });
  final double x1, y1, x2, y2;
  final bool dashed;

  Map<String, dynamic> toJson() => {
    'x1': _r(x1),
    'y1': _r(y1),
    'x2': _r(x2),
    'y2': _r(y2),
    if (dashed) 'd': true,
  };

  factory BoardArrow.fromJson(Map<String, dynamic> m) => BoardArrow(
    x1: (m['x1'] as num).toDouble(),
    y1: (m['y1'] as num).toDouble(),
    x2: (m['x2'] as num).toDouble(),
    y2: (m['y2'] as num).toDouble(),
    dashed: (m['d'] as bool?) ?? false,
  );
}

/// Punto della heatmap (pennello "Fuoco").
@immutable
class HeatPoint {
  const HeatPoint(this.x, this.y);
  final double x, y;
  List<double> toJson() => [_r(x), _r(y)];
  factory HeatPoint.fromJson(List<dynamic> v) =>
      HeatPoint((v[0] as num).toDouble(), (v[1] as num).toDouble());
}

double _r(double v) => (v * 1000).round() / 1000;

/// Lo stato della lavagna: modulo di partenza, squadra, gettoni, frecce, heatmap.
@immutable
class BoardState {
  const BoardState({
    this.module = '4-3-3',
    this.team = 'milanac',
    this.tokens = const [],
    this.arrows = const [],
    this.heat = const [],
  });

  final String module;
  final String team;
  final List<BoardToken> tokens;
  final List<BoardArrow> arrows;
  final List<HeatPoint> heat;

  bool get isEmpty => tokens.isEmpty && arrows.isEmpty && heat.isEmpty;

  BoardState copyWith({
    String? module,
    String? team,
    List<BoardToken>? tokens,
    List<BoardArrow>? arrows,
    List<HeatPoint>? heat,
  }) => BoardState(
    module: module ?? this.module,
    team: team ?? this.team,
    tokens: tokens ?? this.tokens,
    arrows: arrows ?? this.arrows,
    heat: heat ?? this.heat,
  );

  BoardToken? tokenById(String id) =>
      tokens.where((t) => t.id == id).firstOrNull;

  Map<String, dynamic> toJson() => {
    'module': module,
    'team': team,
    'tokens': [for (final t in tokens) t.toJson()],
    'arrows': [for (final a in arrows) a.toJson()],
    'heat': [for (final h in heat) h.toJson()],
  };

  factory BoardState.fromJson(Map<String, dynamic>? m) {
    if (m == null) return const BoardState();
    return BoardState(
      module: (m['module'] as String?) ?? '4-3-3',
      team: (m['team'] as String?) ?? 'milanac',
      tokens: [
        for (final t in (m['tokens'] as List?) ?? const [])
          BoardToken.fromJson((t as Map).cast<String, dynamic>()),
      ],
      arrows: [
        for (final a in (m['arrows'] as List?) ?? const [])
          BoardArrow.fromJson((a as Map).cast<String, dynamic>()),
      ],
      heat: [
        for (final h in (m['heat'] as List?) ?? const [])
          HeatPoint.fromJson(h as List),
      ],
    );
  }

  /// Senza la heatmap: l'anteprima leggera da mettere nel messaggio del replay.
  Map<String, dynamic> toPreviewJson() => {...toJson(), 'heat': const []};
}

/// Un'azione sulla lavagna. Durante la registrazione ogni azione viene salvata con il
/// suo istante, così il replay rifà esattamente le stesse mosse.
sealed class BoardCommand {
  const BoardCommand();

  Map<String, dynamic> toJson();

  static BoardCommand fromJson(Map<String, dynamic> m) => switch (m['k']) {
    'add' => AddToken(
      BoardToken.fromJson((m['token'] as Map).cast<String, dynamic>()),
    ),
    'rm' => RemoveToken(m['id'] as String),
    'ds' => DragStart(m['id'] as String),
    'mv' => MoveToken(
      m['id'] as String,
      (m['x'] as num).toDouble(),
      (m['y'] as num).toDouble(),
    ),
    'de' => const DragEnd(),
    'hs' => const HeatStart(),
    'h' => Heat((m['x'] as num).toDouble(), (m['y'] as num).toDouble()),
    'he' => const HeatEnd(),
    'ar' => AddArrow(
      BoardArrow.fromJson((m['arrow'] as Map).cast<String, dynamic>()),
    ),
    'undo' => const Undo(),
    'clear' => const Clear(),
    'reset' => Reset(
      BoardState.fromJson((m['board'] as Map).cast<String, dynamic>()),
    ),
    _ => throw FormatException('Azione sconosciuta: ${m['k']}'),
  };
}

class AddToken extends BoardCommand {
  const AddToken(this.token);
  final BoardToken token;
  @override
  Map<String, dynamic> toJson() => {'k': 'add', 'token': token.toJson()};
}

class RemoveToken extends BoardCommand {
  const RemoveToken(this.id);
  final String id;
  @override
  Map<String, dynamic> toJson() => {'k': 'rm', 'id': id};
}

/// Inizio del trascinamento di un gettone (punto di annullamento).
class DragStart extends BoardCommand {
  const DragStart(this.id);
  final String id;
  @override
  Map<String, dynamic> toJson() => {'k': 'ds', 'id': id};
}

class MoveToken extends BoardCommand {
  const MoveToken(this.id, this.x, this.y);
  final String id;
  final double x, y;
  @override
  Map<String, dynamic> toJson() => {'k': 'mv', 'id': id, 'x': _r(x), 'y': _r(y)};
}

class DragEnd extends BoardCommand {
  const DragEnd();
  @override
  Map<String, dynamic> toJson() => const {'k': 'de'};
}

/// Inizio di una pennellata di "Fuoco" (punto di annullamento).
class HeatStart extends BoardCommand {
  const HeatStart();
  @override
  Map<String, dynamic> toJson() => const {'k': 'hs'};
}

class Heat extends BoardCommand {
  const Heat(this.x, this.y);
  final double x, y;
  @override
  Map<String, dynamic> toJson() => {'k': 'h', 'x': _r(x), 'y': _r(y)};
}

class HeatEnd extends BoardCommand {
  const HeatEnd();
  @override
  Map<String, dynamic> toJson() => const {'k': 'he'};
}

class AddArrow extends BoardCommand {
  const AddArrow(this.arrow);
  final BoardArrow arrow;
  @override
  Map<String, dynamic> toJson() => {'k': 'ar', 'arrow': arrow.toJson()};
}

class Undo extends BoardCommand {
  const Undo();
  @override
  Map<String, dynamic> toJson() => const {'k': 'undo'};
}

class Clear extends BoardCommand {
  const Clear();
  @override
  Map<String, dynamic> toJson() => const {'k': 'clear'};
}

/// Sostituisce tutta la lavagna (cambio di modulo, apertura di uno schema).
class Reset extends BoardCommand {
  const Reset(this.board);
  final BoardState board;
  @override
  Map<String, dynamic> toJson() => {'k': 'reset', 'board': board.toJson()};
}

/// La lavagna che si disegna: applica le azioni, tiene la cronologia per "Annulla"
/// e, se c'è un ascoltatore, gli passa ogni azione (la registrazione del replay).
class BoardEditor extends ChangeNotifier {
  BoardEditor([BoardState initial = const BoardState()]) : _state = initial;

  BoardState _state;
  final _history = <BoardState>[];

  /// Chi registra le azioni (null = nessuna registrazione).
  void Function(BoardCommand command)? onCommand;

  BoardState get state => _state;
  bool get canUndo => _history.isNotEmpty;

  /// Carica una lavagna (apertura di uno schema, modulo di partenza): niente cronologia,
  /// niente registrazione.
  void load(BoardState s) {
    _state = s;
    _history.clear();
    notifyListeners();
  }

  /// Numero massimo di passi annullabili.
  static const maxHistory = 60;

  void _snapshot() {
    _history.add(_state);
    if (_history.length > maxHistory) _history.removeAt(0);
  }

  void apply(BoardCommand c) {
    switch (c) {
      case AddToken(:final token):
        _snapshot();
        _state = _state.copyWith(
          tokens: [..._state.tokens.where((t) => t.id != token.id), token],
        );
      case RemoveToken(:final id):
        _snapshot();
        _state = _state.copyWith(
          tokens: [..._state.tokens.where((t) => t.id != id)],
        );
      case DragStart():
        _snapshot();
      case MoveToken(:final id, :final x, :final y):
        _state = _state.copyWith(
          tokens: [
            for (final t in _state.tokens) t.id == id ? t.moved(x, y) : t,
          ],
        );
      case DragEnd():
        break;
      case HeatStart():
        _snapshot();
      case Heat(:final x, :final y):
        _state = _state.copyWith(heat: [..._state.heat, HeatPoint(x, y)]);
      case HeatEnd():
        break;
      case AddArrow(:final arrow):
        _snapshot();
        _state = _state.copyWith(arrows: [..._state.arrows, arrow]);
      case Undo():
        if (_history.isNotEmpty) _state = _history.removeLast();
      case Clear():
        _snapshot();
        _state = _state.copyWith(tokens: [], arrows: [], heat: []);
      case Reset(:final board):
        _snapshot();
        _state = board;
    }
    onCommand?.call(c);
    notifyListeners();
  }
}

/// Un'azione con il suo istante (millisecondi dall'inizio della registrazione).
@immutable
class ReplayEvent {
  const ReplayEvent(this.t, this.command);
  final int t;
  final BoardCommand command;
}

/// Il replay: lavagna di partenza, azioni con i tempi, durata. Si salva come JSON
/// (pochi KB) accanto all'audio.
class ReplayData {
  const ReplayData({
    required this.initial,
    required this.events,
    required this.durationMs,
  });

  final BoardState initial;
  final List<ReplayEvent> events;
  final int durationMs;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'ms': durationMs,
    'board': initial.toJson(),
    'events': [
      for (final e in events) {'t': e.t, ...e.command.toJson()},
    ],
  };

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  factory ReplayData.fromJson(Map<String, dynamic> m) => ReplayData(
    initial: BoardState.fromJson((m['board'] as Map?)?.cast<String, dynamic>()),
    durationMs: (m['ms'] as num?)?.toInt() ?? 0,
    events: [
      for (final e in (m['events'] as List?) ?? const [])
        ReplayEvent(
          ((e as Map)['t'] as num).toInt(),
          BoardCommand.fromJson(e.cast<String, dynamic>()),
        ),
    ],
  );

  factory ReplayData.fromBytes(Uint8List bytes) => ReplayData.fromJson(
    (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>(),
  );

  /// La lavagna a un certo istante: rifà le azioni fino a [ms].
  BoardState stateAt(int ms) {
    final editor = BoardEditor(initial);
    for (final e in events) {
      if (e.t > ms) break;
      editor.apply(e.command);
    }
    return editor.state;
  }

  /// Lo stato finale (dopo tutte le azioni).
  BoardState get finalState => stateAt(durationMs + 1);
}

/// Registra le azioni della lavagna con i tempi mentre si parla.
class ReplayRecorder {
  ReplayRecorder(this.initial) : _start = DateTime.now();
  final BoardState initial;
  final DateTime _start;
  final _events = <ReplayEvent>[];

  int get elapsedMs => DateTime.now().difference(_start).inMilliseconds;

  void record(BoardCommand c) => _events.add(ReplayEvent(elapsedMs, c));

  ReplayData finish([int? durationMs]) => ReplayData(
    initial: initial,
    events: List.unmodifiable(_events),
    durationMs: durationMs ?? elapsedMs,
  );
}

/// Lavagna di esempio (demo e test): un 4-3-3 con i gettoni ai loro posti, una freccia
/// e un po' di heatmap sulla fascia sinistra.
BoardState demoBoard() => BoardState(
  module: '4-3-3',
  team: 'milanac',
  tokens: const [
    BoardToken(id: 't0', x: .5, y: .92, playerId: 'p4', label: '1', name: 'Andrea Neri', side: 'milanac'),
    BoardToken(id: 't1', x: .12, y: .72, label: 'TS'),
    BoardToken(id: 't2', x: .37, y: .76, playerId: 'p3', label: '4', name: 'Luca Bianchi'),
    BoardToken(id: 't3', x: .63, y: .76, label: 'DC'),
    BoardToken(id: 't4', x: .88, y: .72, label: 'TD'),
    BoardToken(id: 't5', x: .25, y: .5, playerId: 'demo', label: '10', name: 'Demo Direttivo'),
    BoardToken(id: 't6', x: .5, y: .56, label: 'CDC'),
    BoardToken(id: 't7', x: .75, y: .5, label: 'CC'),
    BoardToken(id: 't8', x: .18, y: .24, label: 'AS'),
    BoardToken(id: 't9', x: .5, y: .17, playerId: 'p2', label: '9', name: 'Marco Rossi'),
    BoardToken(id: 't10', x: .82, y: .24, label: 'AD'),
    BoardToken(id: 'a1', x: .5, y: .3, label: 'A', side: 'avversari'),
  ],
  arrows: const [BoardArrow(x1: .5, y1: .92, x2: .37, y2: .76), BoardArrow(x1: .37, y1: .76, x2: .12, y2: .6, dashed: true)],
  heat: const [HeatPoint(.12, .55), HeatPoint(.13, .5), HeatPoint(.15, .45), HeatPoint(.16, .4), HeatPoint(.15, .36)],
);

/// Replay di esempio (demo): venti secondi in cui il CDC si abbassa tra i centrali,
/// il terzino sale e compare una freccia.
ReplayData demoReplay() {
  final initial = demoBoard().copyWith(arrows: const [], heat: const []);
  final events = <ReplayEvent>[
    const ReplayEvent(1000, DragStart('t6')),
    for (var i = 1; i <= 20; i++)
      ReplayEvent(1000 + i * 100, MoveToken('t6', .5, .56 + .18 * i / 20)),
    const ReplayEvent(3100, DragEnd()),
    const ReplayEvent(5000, DragStart('t1')),
    for (var i = 1; i <= 20; i++)
      ReplayEvent(5000 + i * 100, MoveToken('t1', .12, .72 - .3 * i / 20)),
    const ReplayEvent(7100, DragEnd()),
    const ReplayEvent(9000, HeatStart()),
    for (var i = 0; i < 12; i++) ReplayEvent(9000 + i * 150, Heat(.12 + i * .01, .42 - i * .012)),
    const ReplayEvent(10900, HeatEnd()),
    const ReplayEvent(13000, AddArrow(BoardArrow(x1: .5, y1: .92, x2: .5, y2: .74))),
    const ReplayEvent(16000, AddArrow(BoardArrow(x1: .5, y1: .74, x2: .14, y2: .44, dashed: true))),
  ];
  return ReplayData(initial: initial, events: events, durationMs: 20000);
}
