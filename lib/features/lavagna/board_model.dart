import 'dart:convert';
import 'dart:math';

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

/// Il pallone. [x] e [y] sono il punto dove si disegna: al piede di chi ce l'ha
/// ([holder]), altrimenti dove è stato lasciato.
@immutable
class BoardBall {
  const BoardBall({required this.x, required this.y, this.holder});
  final double x, y;

  /// Il gettone che ha la palla al piede (null = palla libera).
  final String? holder;

  /// Sul dischetto del centrocampo, libero.
  static const kickOff = BoardBall(x: .5, y: .5);

  /// Lo stesso punto, senza più nessuno che lo porta.
  BoardBall free() => holder == null ? this : BoardBall(x: x, y: y);

  Map<String, dynamic> toJson() => {
    'x': _r(x),
    'y': _r(y),
    if (holder != null) 'h': holder,
  };

  /// Null se manca o è malformato: il pallone è un'aggiunta e non deve impedire di
  /// aprire uno schema (o una versione dell'app più nuova lo scrive diverso).
  static BoardBall? tryFromJson(Object? m) {
    if (m is! Map) return null;
    final x = m['x'], y = m['y'], h = m['h'];
    if (x is! num || y is! num) return null;
    return BoardBall(
      x: x.toDouble(),
      y: y.toDouble(),
      holder: h is String ? h : null,
    );
  }
}

/// Il pallone al piede di [t]: sul bordo del gettone, circa un raggio a destra e
/// mezzo raggio sotto il centro, così non copre né il numero né il nome (verso
/// l'interno vicino ai bordi del campo).
BoardBall ballAtFeet(BoardToken t) {
  const dx = .045, dy = .016;
  return BoardBall(
    x: (t.x > .93 ? t.x - dx : t.x + dx).clamp(0.0, 1.0),
    y: (t.y > .96 ? t.y - dy : t.y + dy).clamp(0.0, 1.0),
    holder: t.id,
  );
}

/// Distanza sul campo in larghezze del campo: in y la stessa differenza vale circa
/// una volta e mezza (105 m di lunghezza su 68 di larghezza).
double fieldDistance(double dx, double dy) => sqrt(dx * dx + dy * dy * 2.25);

/// Che cosa ha fatto il pallone: passaggio, conduzione (palla al piede) o tiro.
enum BallLineKind {
  pass('p'),
  carry('c'),
  shot('s');

  const BallLineKind(this.code);

  /// Nel JSON.
  final String code;

  static BallLineKind? parse(Object? code) =>
      values.where((k) => k.code == code).firstOrNull;
}

/// La linea lasciata da un'azione del pallone, con il suo numero (1, 2, 3...). Da un
/// gettone parte dal suo centro ([fromPlayer]) e a un gettone arriva al suo centro
/// ([toPlayer]): il disegno la accorcia lì, così né la punta né il numero finiscono
/// sotto il gettone.
@immutable
class BallLine {
  const BallLine({
    required this.kind,
    required this.n,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.fromPlayer = false,
    this.toPlayer = false,
  });

  final BallLineKind kind;
  final int n;
  final double x1, y1, x2, y2;
  final bool fromPlayer, toPlayer;

  Map<String, dynamic> toJson() => {
    'k': kind.code,
    'n': n,
    'x1': _r(x1),
    'y1': _r(y1),
    'x2': _r(x2),
    'y2': _r(y2),
    if (fromPlayer) 'a': true,
    if (toPlayer) 'b': true,
  };

  /// Null se malformata (o di un tipo che questa versione non conosce): si salta.
  static BallLine? tryFromJson(Object? m) {
    if (m is! Map) return null;
    final kind = BallLineKind.parse(m['k']);
    final n = m['n'], x1 = m['x1'], y1 = m['y1'], x2 = m['x2'], y2 = m['y2'];
    if (kind == null ||
        n is! num ||
        !n.isFinite ||
        x1 is! num ||
        y1 is! num ||
        x2 is! num ||
        y2 is! num) {
      return null;
    }
    return BallLine(
      kind: kind,
      n: n.clamp(0, 99999).toInt(),
      x1: x1.toDouble(),
      y1: y1.toDouble(),
      x2: x2.toDouble(),
      y2: y2.toDouble(),
      fromPlayer: m['a'] == true,
      toPlayer: m['b'] == true,
    );
  }
}

/// Gli interruttori di "Vista": cosa si disegna sopra il campo. Si salvano con la
/// lavagna, così schemi e replay mostrano le stesse cose. Per aggiungerne uno basta
/// un valore qui (più il suo disegno): il foglio "Vista" li elenca tutti.
enum BoardOverlay {
  ballLines(
    'bl',
    'Linee della palla',
    'Passaggi, conduzioni (ondulate) e tiri, numerati.',
    on: true,
  );

  const BoardOverlay(this.key, this.label, this.description, {this.on = false});

  /// Nel JSON.
  final String key;
  final String label;
  final String description;

  /// Acceso di serie.
  final bool on;
}

double _r(double v) => (v * 1000).round() / 1000;

/// Lo stato della lavagna: modulo di partenza, squadra, gettoni, frecce, heatmap,
/// pallone con le sue linee e la vista.
@immutable
class BoardState {
  const BoardState({
    this.module = '4-3-3',
    this.team = 'milanac',
    this.tokens = const [],
    this.arrows = const [],
    this.heat = const [],
    this.ball,
    this.lines = const [],
    this.view = const {},
  });

  final String module;
  final String team;
  final List<BoardToken> tokens;
  final List<BoardArrow> arrows;
  final List<HeatPoint> heat;

  /// Il pallone (null negli schemi salvati prima che ci fosse: non si aggiunge da
  /// solo, lo mette l'allenatore).
  final BoardBall? ball;

  /// Le linee del pallone (passaggi, conduzioni, tiri), dalla più vecchia.
  final List<BallLine> lines;

  /// Gli interruttori di "Vista" diversi da quelli di serie (chiave → acceso). Le
  /// chiavi sconosciute (di una versione più nuova) restano come sono.
  final Map<String, bool> view;

  /// Niente di disegnato (il pallone da solo non conta: c'è sempre).
  bool get isEmpty =>
      tokens.isEmpty && arrows.isEmpty && heat.isEmpty && lines.isEmpty;

  /// Massimo dei punti della heatmap: oltre, lo schema supererebbe il limite di
  /// 300 KB del database (e la lavagna rallenterebbe).
  static const maxHeat = 2000;

  /// Linee del pallone che restano sul campo: oltre, si tolgono le più vecchie (la
  /// lavagna resta leggibile).
  static const maxBallLines = 30;

  bool get heatFull => heat.length >= maxHeat;

  /// In (x, y) il colore della heatmap è già pieno: un altro punto non si vedrebbe
  /// (diradamento: dove si insiste a lungo non si accumulano punti inutili).
  bool heatSaturatedAt(double x, double y) {
    var near = 0;
    for (final h in heat) {
      if ((h.x - x).abs() < .02 && (h.y - y).abs() < .02 && ++near >= 12) {
        return true;
      }
    }
    return false;
  }

  /// L'interruttore [o] di "Vista" è acceso.
  bool shows(BoardOverlay o) => view[o.key] ?? o.on;

  /// Il numero della prossima azione del pallone.
  int get nextBallNumber => lines.isEmpty ? 1 : lines.last.n + 1;

  /// Le linee con [line] in fondo (e senza le più vecchie oltre il massimo).
  List<BallLine> linesWith(BallLine line) {
    final all = [...lines, line];
    return all.length > maxBallLines
        ? all.sublist(all.length - maxBallLines)
        : all;
  }

  /// Copia con qualche campo cambiato. Il pallone si passa come funzione, così si
  /// può anche togliere: `copyWith(ball: () => null)`.
  BoardState copyWith({
    String? module,
    String? team,
    List<BoardToken>? tokens,
    List<BoardArrow>? arrows,
    List<HeatPoint>? heat,
    BoardBall? Function()? ball,
    List<BallLine>? lines,
    Map<String, bool>? view,
  }) => BoardState(
    module: module ?? this.module,
    team: team ?? this.team,
    tokens: tokens ?? this.tokens,
    arrows: arrows ?? this.arrows,
    heat: heat ?? this.heat,
    ball: ball != null ? ball() : this.ball,
    lines: lines ?? this.lines,
    view: view ?? this.view,
  );

  BoardToken? tokenById(String id) =>
      tokens.where((t) => t.id == id).firstOrNull;

  /// La versione del formato che serve per leggerla: 2 con il pallone (o le sue
  /// linee, o la vista), altrimenti 1.
  int get version =>
      ball != null || lines.isNotEmpty || view.isNotEmpty ? 2 : 1;

  Map<String, dynamic> toJson() => {
    'module': module,
    'team': team,
    'tokens': [for (final t in tokens) t.toJson()],
    'arrows': [for (final a in arrows) a.toJson()],
    'heat': [for (final h in heat) h.toJson()],
    if (ball != null) 'ball': ball!.toJson(),
    if (lines.isNotEmpty) 'lines': [for (final l in lines) l.toJson()],
    if (view.isNotEmpty) 'view': view,
  };

  factory BoardState.fromJson(Map<String, dynamic>? m) {
    if (m == null) return const BoardState();
    final view = m['view'];
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
      // Pallone, linee e vista arrivano dopo: se sono malformati si lasciano fuori
      // invece di perdere tutto lo schema.
      ball: BoardBall.tryFromJson(m['ball']),
      lines: [
        if (m['lines'] case final List lines)
          for (final l in lines) ?BallLine.tryFromJson(l),
      ],
      view: {
        if (view is Map)
          for (final MapEntry(:key, :value) in view.entries)
            if (key is String && value is bool) key: value,
      },
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

  /// La versione del replay che serve per rifarla: 2 per il pallone e la vista.
  int get version => switch (this) {
    PlaceBall() ||
    GrabBall() ||
    MoveBall() ||
    DropBall() ||
    KickBall() ||
    ClearBallLines() ||
    SetView() => 2,
    Reset(:final board) => board.version,
    _ => 1,
  };

  /// L'azione letta dal JSON; null se è di un tipo che questa versione dell'app non
  /// conosce (di una versione più nuova): si salta.
  static BoardCommand? fromJson(Map<String, dynamic> m) => switch (m['k']) {
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
    'ball' => PlaceBall(BoardBall.tryFromJson(m['ball'])),
    'bg' => const GrabBall(),
    'bm' => MoveBall((m['x'] as num).toDouble(), (m['y'] as num).toDouble()),
    'bd' => DropBall(m['to'] as String?),
    'kick' => KickBall(
      x: (m['x'] as num).toDouble(),
      y: (m['y'] as num).toDouble(),
      to: m['to'] as String?,
      shot: m['s'] == true,
    ),
    'bl0' => const ClearBallLines(),
    'view' => SetView(m['o'] as String, m['on'] as bool),
    _ => null,
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
  Map<String, dynamic> toJson() => {
    'k': 'mv',
    'id': id,
    'x': _r(x),
    'y': _r(y),
  };
}

/// Fine del trascinamento: se il gettone aveva la palla al piede e si è spostato,
/// resta la linea ondulata della conduzione.
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

/// "Pulisci": via gettoni, frecce, heatmap e linee; il pallone torna a centrocampo.
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

/// Mette il pallone (dal foglio dei gettoni o del pallone), lo rimette a
/// centrocampo o lo toglie (null).
class PlaceBall extends BoardCommand {
  const PlaceBall(this.ball);
  final BoardBall? ball;
  @override
  Map<String, dynamic> toJson() => {
    'k': 'ball',
    if (ball != null) 'ball': ball!.toJson(),
  };
}

/// Inizio del trascinamento del pallone (punto di annullamento): chi l'aveva al piede
/// lo lascia.
class GrabBall extends BoardCommand {
  const GrabBall();
  @override
  Map<String, dynamic> toJson() => const {'k': 'bg'};
}

class MoveBall extends BoardCommand {
  const MoveBall(this.x, this.y);
  final double x, y;
  @override
  Map<String, dynamic> toJson() => {'k': 'bm', 'x': _r(x), 'y': _r(y)};
}

/// Fine del trascinamento del pallone: lasciato su un gettone ([to]), gli va al piede.
class DropBall extends BoardCommand {
  const DropBall([this.to]);
  final String? to;
  @override
  Map<String, dynamic> toJson() => {'k': 'bd', 'to': ?to};
}

/// Passaggio a un gettone ([to]), nello spazio o tiro in porta ([shot]): il pallone
/// parte da dov'è (dal piede di chi ce l'ha) e arriva subito, in un'azione sola; il
/// volo lo disegna la lavagna. [x] e [y] sono l'arrivo (il gettone, il punto
/// dell'erba o della porta).
class KickBall extends BoardCommand {
  const KickBall({
    required this.x,
    required this.y,
    this.to,
    this.shot = false,
  });
  final double x, y;
  final String? to;
  final bool shot;
  @override
  Map<String, dynamic> toJson() => {
    'k': 'kick',
    'x': _r(x),
    'y': _r(y),
    'to': ?to,
    if (shot) 's': true,
  };
}

/// Via le linee del pallone (la numerazione riparte da 1).
class ClearBallLines extends BoardCommand {
  const ClearBallLines();
  @override
  Map<String, dynamic> toJson() => const {'k': 'bl0'};
}

/// Un interruttore di "Vista" ([key] di [BoardOverlay]). Non si annulla: è come si
/// guarda la lavagna, non una mossa.
class SetView extends BoardCommand {
  const SetView(this.key, this.on);
  final String key;
  final bool on;
  @override
  Map<String, dynamic> toJson() => {'k': 'view', 'o': key, 'on': on};
}

/// Durata del volo del pallone (passaggi e tiri), dal vivo come nel replay.
const ballFlightMs = 450;

/// Un passaggio o un tiro appena fatto: da dove è partito il pallone e il numero
/// della sua linea. Serve solo a disegnare il volo: lo stato è già quello d'arrivo.
@immutable
class BallKick {
  const BallKick(this.fromX, this.fromY, this.line);
  final double fromX, fromY;
  final int line;
}

/// Spostamento minimo di chi ha la palla al piede perché resti la linea della
/// conduzione (in larghezze del campo, circa 4 metri).
const carryMinDistance = .06;

/// La lavagna che si disegna: applica le azioni, tiene la cronologia per "Annulla"
/// e, se c'è un ascoltatore, gli passa ogni azione (la registrazione del replay).
class BoardEditor extends ChangeNotifier
    implements ValueListenable<BoardState> {
  BoardEditor([BoardState initial = const BoardState()]) : _state = initial;

  BoardState _state;
  final _history = <BoardState>[];

  /// Il gettone che si sta trascinando e da dove è partito (per la conduzione).
  (String, double, double)? _drag;

  BallKick? _kick;

  /// Chi registra le azioni (null = nessuna registrazione).
  void Function(BoardCommand command)? onCommand;

  BoardState get state => _state;

  @override
  BoardState get value => _state;

  bool get canUndo => _history.isNotEmpty;

  /// L'ultimo passaggio o tiro, finché il pallone non fa altro (lo si prende, si
  /// annulla...): chi disegna ne fa vedere il volo. Un oggetto nuovo per ogni tiro.
  BallKick? get lastKick => _kick;

  /// Carica una lavagna (apertura di uno schema, modulo di partenza): niente cronologia,
  /// niente registrazione.
  void load(BoardState s) {
    _state = s;
    _history.clear();
    _drag = null;
    _kick = null;
    notifyListeners();
  }

  /// Inizia a registrare il replay dalla lavagna attuale. La cronologia di "Annulla"
  /// riparte da qui: il replay comincia da questa lavagna e non conosce le mosse di
  /// prima, quindi un annullamento nel vivo deve togliere solo mosse registrate.
  ReplayRecorder startRecording({int Function()? clock}) {
    _history.clear();
    final recorder = ReplayRecorder(_state, clock: clock);
    onCommand = recorder.record;
    notifyListeners();
    return recorder;
  }

  /// Numero massimo di passi annullabili.
  static const maxHistory = 60;

  void _snapshot() {
    _history.add(_state);
    if (_history.length > maxHistory) _history.removeAt(0);
  }

  /// Il pallone di [token], se è lui ad averlo al piede, segue il gettone.
  BoardBall? Function()? _follow(BoardToken token) {
    final ball = _state.ball;
    return ball?.holder == token.id ? () => ballAtFeet(token) : null;
  }

  /// Il pallone messo così com'è; se ha un gettone, al suo piede.
  BoardBall? _placed(BoardBall? ball) {
    final holder = ball?.holder == null
        ? null
        : _state.tokenById(ball!.holder!);
    return holder != null ? ballAtFeet(holder) : ball?.free();
  }

  void apply(BoardCommand c) {
    switch (c) {
      case AddToken(:final token):
        _snapshot();
        _state = _state.copyWith(
          tokens: [..._state.tokens.where((t) => t.id != token.id), token],
          ball: _follow(token),
        );
      case RemoveToken(:final id):
        _snapshot();
        // Il pallone del giocatore tolto resta dov'era, libero.
        final ball = _state.ball;
        _state = _state.copyWith(
          tokens: [..._state.tokens.where((t) => t.id != id)],
          ball: ball?.holder == id ? ball!.free : null,
        );
      case DragStart(:final id):
        _snapshot();
        final t = _state.tokenById(id);
        _drag = t == null ? null : (id, t.x, t.y);
      case MoveToken(:final id, :final x, :final y):
        final moved = _state.tokenById(id)?.moved(x, y);
        _state = _state.copyWith(
          tokens: [
            for (final t in _state.tokens) t.id == id ? t.moved(x, y) : t,
          ],
          ball: moved == null ? null : _follow(moved),
        );
      case DragEnd():
        _endCarry();
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
        // La vista resta com'è: "Annulla" toglie mosse, non cambia come si guarda.
        if (_history.isNotEmpty) {
          _state = _history.removeLast().copyWith(view: _state.view);
        }
        _kick = null;
      case Clear():
        _snapshot();
        _state = _state.copyWith(
          tokens: [],
          arrows: [],
          heat: [],
          lines: [],
          ball: () => BoardBall.kickOff,
        );
        _kick = null;
      case Reset(:final board):
        _snapshot();
        _state = board;
        _drag = null;
        _kick = null;
      case PlaceBall(:final ball):
        _snapshot();
        _state = _state.copyWith(ball: () => _placed(ball));
        _kick = null;
      case GrabBall():
        final ball = _state.ball;
        if (ball != null) {
          _snapshot();
          _state = _state.copyWith(ball: ball.free);
        }
        _kick = null;
      case MoveBall(:final x, :final y):
        if (_state.ball != null) {
          _state = _state.copyWith(
            ball: () => BoardBall(x: x, y: y),
          );
        }
      case DropBall(:final to):
        final holder = to == null ? null : _state.tokenById(to);
        if (holder != null && _state.ball != null) {
          _state = _state.copyWith(ball: () => ballAtFeet(holder));
        }
      case KickBall():
        _kickBall(c);
      case ClearBallLines():
        _snapshot();
        _state = _state.copyWith(lines: []);
        _kick = null;
      case SetView(:final key, :final on):
        final o = BoardOverlay.values.where((o) => o.key == key).firstOrNull;
        _state = _state.copyWith(
          view: {
            for (final e in _state.view.entries)
              if (e.key != key) e.key: e.value,
            // Uguale a quello di serie non serve scriverlo.
            if (on != o?.on) key: on,
          },
        );
    }
    onCommand?.call(c);
    notifyListeners();
  }

  /// Passaggio o tiro: la linea numerata dal piede di chi ha la palla (o da dove
  /// è, se è libera) all'arrivo; il pallone è subito lì.
  void _kickBall(KickBall c) {
    final ball = _state.ball;
    if (ball == null) return;
    _snapshot();
    final from = ball.holder == null ? null : _state.tokenById(ball.holder!);
    final to = c.shot || c.to == null ? null : _state.tokenById(c.to!);
    final line = BallLine(
      kind: c.shot ? BallLineKind.shot : BallLineKind.pass,
      n: _state.nextBallNumber,
      x1: from?.x ?? ball.x,
      y1: from?.y ?? ball.y,
      x2: to?.x ?? c.x,
      y2: to?.y ?? c.y,
      fromPlayer: from != null,
      toPlayer: to != null,
    );
    _kick = BallKick(ball.x, ball.y, line.n);
    _state = _state.copyWith(
      ball: () => to != null ? ballAtFeet(to) : BoardBall(x: c.x, y: c.y),
      lines: _state.linesWith(line),
    );
  }

  /// Fine di un trascinamento: chi aveva la palla al piede e si è spostato abbastanza
  /// lascia la linea ondulata della conduzione (nello stesso passo di "Annulla").
  void _endCarry() {
    final drag = _drag;
    _drag = null;
    if (drag == null) return;
    final (id, x0, y0) = drag;
    final t = _state.tokenById(id);
    if (t == null || _state.ball?.holder != id) return;
    if (fieldDistance(t.x - x0, t.y - y0) < carryMinDistance) return;
    _state = _state.copyWith(
      lines: _state.linesWith(
        BallLine(
          kind: BallLineKind.carry,
          n: _state.nextBallNumber,
          x1: x0,
          y1: y0,
          x2: t.x,
          y2: t.y,
          fromPlayer: true,
          toPlayer: true,
        ),
      ),
    );
  }
}

/// Un'azione con il suo istante (millisecondi dall'inizio della registrazione).
@immutable
class ReplayEvent {
  const ReplayEvent(this.t, this.command);
  final int t;
  final BoardCommand command;
}

/// Il replay è di una versione dell'app più nuova (formato che questa non conosce).
class ReplayTooNew implements Exception {
  const ReplayTooNew(this.version);
  final int version;

  @override
  String toString() => 'Replay in un formato più nuovo ($version)';
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

  /// L'ultima versione del formato che questa app sa leggere (2: il pallone).
  static const supportedVersion = 2;

  /// La versione del formato: 2 se c'è il pallone (nella lavagna di partenza o nelle
  /// azioni), altrimenti 1.
  int get version =>
      max(initial.version, events.fold(1, (v, e) => max(v, e.command.version)));

  Map<String, dynamic> toJson() => {
    'v': version,
    'ms': durationMs,
    'board': initial.toJson(),
    'events': [
      for (final e in events) {'t': e.t, ...e.command.toJson()},
    ],
  };

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Lancia [ReplayTooNew] se il replay è di una versione più nuova; le azioni di un
  /// tipo sconosciuto si saltano.
  factory ReplayData.fromJson(Map<String, dynamic> m) {
    final v = m['v'];
    if (v is num && v > supportedVersion) throw ReplayTooNew(v.toInt());
    final events = [
      for (final e in (m['events'] as List?) ?? const [])
        if (BoardCommand.fromJson((e as Map).cast<String, dynamic>())
            case final command?)
          ReplayEvent((e['t'] as num).toInt(), command),
    ];
    return ReplayData(
      initial: BoardState.fromJson(
        (m['board'] as Map?)?.cast<String, dynamic>(),
      ),
      // I replay registrati prima avevano la durata arrotondata al secondo, a volte
      // prima dell'ultima mossa: si allunga fino a lei, così si vede.
      durationMs: max((m['ms'] as num?)?.toInt() ?? 0, lastEventMs(events)),
      events: events,
    );
  }

  factory ReplayData.fromBytes(Uint8List bytes) => ReplayData.fromJson(
    (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>(),
  );

  /// Istante dell'ultima azione (0 se non ce ne sono).
  static int lastEventMs(List<ReplayEvent> events) =>
      events.fold(0, (m, e) => max(m, e.t));

  /// La lavagna a un certo istante: rifà le azioni fino a [ms].
  BoardState stateAt(int ms) {
    final editor = BoardEditor(initial);
    for (final e in events) {
      if (e.t > ms) break;
      editor.apply(e.command);
    }
    final state = editor.state;
    editor.dispose();
    return state;
  }

  /// Lo stato finale (dopo tutte le azioni).
  BoardState get finalState => stateAt(max(durationMs, lastEventMs(events)));
}

/// Registra le azioni della lavagna con i tempi mentre si parla.
class ReplayRecorder {
  /// [clock] dà i millisecondi trascorsi (nei test); di norma un cronometro, che non
  /// risente dei cambi dell'ora del telefono.
  ReplayRecorder(this.initial, {int Function()? clock})
    : _clock = clock ?? _stopwatch();
  final BoardState initial;
  final int Function() _clock;
  final _events = <ReplayEvent>[];

  static int Function() _stopwatch() {
    final s = Stopwatch()..start();
    return () => s.elapsedMilliseconds;
  }

  int get elapsedMs => _clock();

  void record(BoardCommand c) => _events.add(ReplayEvent(elapsedMs, c));

  /// Il replay registrato. La durata è in millisecondi (quella della voce, se data)
  /// e non finisce mai prima dell'ultima azione: altrimenti l'ultima mossa non si
  /// vedrebbe.
  ReplayData finish([int? durationMs]) => ReplayData(
    initial: initial,
    events: List.unmodifiable(_events),
    durationMs: max(durationMs ?? elapsedMs, ReplayData.lastEventMs(_events)),
  );
}

/// Lavagna di esempio (demo e test): un 4-3-3 con i gettoni ai loro posti, due frecce,
/// un po' di heatmap sulla fascia sinistra e un'azione del pallone: portiere, centrale,
/// mediano, ala sinistra che conduce e tira.
BoardState demoBoard() => BoardState(
  module: '4-3-3',
  team: 'milanac',
  tokens: const [
    BoardToken(
      id: 't0',
      x: .5,
      y: .92,
      playerId: 'p4',
      label: '1',
      name: 'Andrea Neri',
      side: 'milanac',
    ),
    BoardToken(id: 't1', x: .12, y: .72, label: 'TS'),
    BoardToken(
      id: 't2',
      x: .37,
      y: .76,
      playerId: 'p3',
      label: '4',
      name: 'Luca Bianchi',
    ),
    BoardToken(id: 't3', x: .63, y: .76, label: 'DC'),
    BoardToken(id: 't4', x: .88, y: .72, label: 'TD'),
    BoardToken(
      id: 't5',
      x: .25,
      y: .5,
      playerId: 'demo',
      label: '10',
      name: 'Demo Direttivo',
    ),
    BoardToken(id: 't6', x: .5, y: .56, label: 'CDC'),
    BoardToken(id: 't7', x: .75, y: .5, label: 'CC'),
    BoardToken(id: 't8', x: .18, y: .24, label: 'AS'),
    BoardToken(
      id: 't9',
      x: .5,
      y: .17,
      playerId: 'p2',
      label: '9',
      name: 'Marco Rossi',
    ),
    BoardToken(id: 't10', x: .82, y: .24, label: 'AD'),
    BoardToken(id: 'a1', x: .5, y: .3, label: 'A', side: 'avversari'),
  ],
  arrows: const [
    BoardArrow(x1: .88, y1: .72, x2: .88, y2: .45),
    BoardArrow(x1: .37, y1: .76, x2: .12, y2: .6, dashed: true),
  ],
  heat: const [
    HeatPoint(.12, .55),
    HeatPoint(.13, .5),
    HeatPoint(.15, .45),
    HeatPoint(.16, .4),
    HeatPoint(.15, .36),
  ],
  // Il tiro dell'ala è finito in porta.
  ball: const BoardBall(x: .48, y: 0),
  lines: const [
    BallLine(
      kind: BallLineKind.pass,
      n: 1,
      x1: .5,
      y1: .92,
      x2: .37,
      y2: .76,
      fromPlayer: true,
      toPlayer: true,
    ),
    BallLine(
      kind: BallLineKind.pass,
      n: 2,
      x1: .37,
      y1: .76,
      x2: .5,
      y2: .56,
      fromPlayer: true,
      toPlayer: true,
    ),
    BallLine(
      kind: BallLineKind.pass,
      n: 3,
      x1: .5,
      y1: .56,
      x2: .14,
      y2: .4,
      fromPlayer: true,
      toPlayer: true,
    ),
    BallLine(
      kind: BallLineKind.carry,
      n: 4,
      x1: .14,
      y1: .4,
      x2: .18,
      y2: .24,
      fromPlayer: true,
      toPlayer: true,
    ),
    BallLine(
      kind: BallLineKind.shot,
      n: 5,
      x1: .18,
      y1: .24,
      x2: .48,
      y2: 0,
      fromPlayer: true,
    ),
  ],
);

/// Replay di esempio (demo): venti secondi in cui il CDC si abbassa tra i centrali,
/// il portiere apre sul centrale che la dà al CDC, il terzino sale, riceve, conduce e
/// passa al centravanti che tira; poi la heatmap e le frecce degli esterni a destra.
ReplayData demoReplay() {
  final board = demoBoard();
  final initial = board.copyWith(
    arrows: const [],
    heat: const [],
    lines: const [],
    ball: () => ballAtFeet(board.tokenById('t0')!),
  );
  final events = <ReplayEvent>[
    const ReplayEvent(1000, DragStart('t6')),
    for (var i = 1; i <= 20; i++)
      ReplayEvent(1000 + i * 100, MoveToken('t6', .5, .56 + .18 * i / 20)),
    const ReplayEvent(3100, DragEnd()),
    const ReplayEvent(3600, KickBall(x: .37, y: .76, to: 't2')),
    const ReplayEvent(4400, KickBall(x: .5, y: .74, to: 't6')),
    const ReplayEvent(5000, DragStart('t1')),
    for (var i = 1; i <= 20; i++)
      ReplayEvent(5000 + i * 100, MoveToken('t1', .12, .72 - .3 * i / 20)),
    const ReplayEvent(7100, DragEnd()),
    const ReplayEvent(7500, KickBall(x: .12, y: .42, to: 't1')),
    const ReplayEvent(8000, DragStart('t1')),
    for (var i = 1; i <= 8; i++)
      ReplayEvent(
        8000 + i * 100,
        MoveToken('t1', .12 + .1 * i / 8, .42 - .12 * i / 8),
      ),
    const ReplayEvent(8900, DragEnd()),
    const ReplayEvent(9300, KickBall(x: .5, y: .17, to: 't9')),
    const ReplayEvent(10000, KickBall(x: .52, y: 0, shot: true)),
    const ReplayEvent(11000, HeatStart()),
    for (var i = 0; i < 12; i++)
      ReplayEvent(11000 + i * 150, Heat(.12 + i * .01, .42 - i * .012)),
    const ReplayEvent(12900, HeatEnd()),
    const ReplayEvent(
      13000,
      AddArrow(BoardArrow(x1: .88, y1: .72, x2: .88, y2: .42)),
    ),
    const ReplayEvent(
      16000,
      AddArrow(BoardArrow(x1: .82, y1: .24, x2: .68, y2: .1, dashed: true)),
    ),
  ];
  return ReplayData(initial: initial, events: events, durationMs: 20000);
}
