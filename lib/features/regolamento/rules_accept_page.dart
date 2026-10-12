import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/push/device_tokens.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import 'parchment.dart';
import 'rules_reader.dart';
import 'rules_repository.dart';

/// Tempo minimo di lettura: non si mostra, ma prima non si può accettare.
const rulesReadingTime = Duration(minutes: 2);

/// Accettazione del regolamento: si entra nel club (o si continua a usarlo dopo
/// una nuova versione) solo dopo averlo letto fino in fondo e per almeno 2 minuti.
class RulesAcceptPage extends ConsumerStatefulWidget {
  const RulesAcceptPage({super.key});

  @override
  ConsumerState<RulesAcceptPage> createState() => _RulesAcceptPageState();
}

class _RulesAcceptPageState extends ConsumerState<RulesAcceptPage> {
  final _scroll = ScrollController();
  late final AppLifecycleListener _lifecycle;
  bool _foreground = true;

  /// Secondi di lettura: contano solo con il testo sullo schermo e l'app in primo piano.
  Timer? _ticker;
  int _readSeconds = 0;

  /// Versione sullo schermo: se ne arriva un'altra si legge da capo.
  int? _version;
  bool _reachedEnd = false;
  bool _saving = false;

  bool get _timeOk => _readSeconds >= rulesReadingTime.inSeconds;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _updateTicker();
      },
    );
    _scroll.addListener(_checkEnd);
    ref.listenManual(
      latestRulesProvider,
      (_, next) => _onRules(next.value),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onRules(RulesVersion? version) {
    final number = version?.number;
    if (number != null && _version != null && number != _version) {
      // Nuova versione (es. pubblicata mentre si leggeva): fino in fondo e per il tempo
      // minimo, da capo.
      setState(() {
        _readSeconds = 0;
        _reachedEnd = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    if (number != null) _version = number;
    _updateTicker();
  }

  void _updateTicker() {
    final reading = _version != null && _foreground && !_timeOk && mounted;
    if (!reading) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      _readSeconds++;
      if (!_timeOk) return;
      _ticker?.cancel();
      _ticker = null;
      if (mounted) setState(() {});
    });
  }

  /// Fondo raggiunto scorrendo, oppure subito se il testo sta tutto nello schermo
  /// (controllato a ogni cambio di misure: primo disegno, nuova versione, rotazione).
  void _checkEnd([ScrollMetrics? metrics]) {
    if (_reachedEnd || !mounted) return;
    final m = metrics ?? (_scroll.hasClients ? _scroll.position : null);
    if (m == null || !m.hasContentDimensions) return;
    if (m.pixels >= m.maxScrollExtent - 24) {
      setState(() => _reachedEnd = true);
    }
  }

  Future<void> _accept(RulesVersion version) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_timeOk) {
      HapticFeedback.heavyImpact();
      messenger.hideCurrentMaterialBanner();
      messenger.showMaterialBanner(
        MaterialBanner(
          backgroundColor: MilanacColors.redDark,
          leading: const Icon(Icons.hourglass_top_rounded, color: Colors.white),
          content: const Text(
            'Servono 2 minuti di lettura: continua a leggere il regolamento e riprova.',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: messenger.hideCurrentMaterialBanner,
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(rulesRepositoryProvider).accept(version.number);
    } catch (e) {
      if (!mounted) return;
      if (isOutdatedRulesError(e)) {
        // Nel frattempo il Direttivo ha pubblicato un'altra versione: si carica e si
        // legge quella.
        ref.invalidate(latestRulesProvider);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'È uscita una nuova versione del regolamento: leggila e accetta.',
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(e, action: 'Accettazione non riuscita'),
            ),
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    HapticFeedback.mediumImpact();
    messenger.hideCurrentMaterialBanner();
    if (!mounted) return;
    // Il router apre la Home appena il profilo riletto ha la versione accettata, senza
    // aspettare il tempo reale; in demo andiamo noi.
    ref.invalidate(profileProvider);
    if (AppConfig.isDemo) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(latestRulesProvider);
    return StadiumBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('REGOLAMENTO'),
          automaticallyImplyLeading: false,
          actions: [
            if (!AppConfig.isDemo)
              IconButton(
                tooltip: 'Esci dall\'account',
                icon: const Icon(Icons.logout_rounded),
                onPressed: () => logout(ref),
              ),
          ],
        ),
        body: !rules.hasValue && rules.hasError
            // Senza testo da mostrare l'errore si vede anche mentre si riprova da soli.
            ? ErrorRetry(
                message: friendlyError(
                  rules.error!,
                  action: 'Impossibile caricare il regolamento',
                ),
                onRetry: () => ref.invalidate(latestRulesProvider),
              )
            : AsyncView<RulesVersion?>(
                value: rules,
                onRetry: () => ref.invalidate(latestRulesProvider),
                data: (version) =>
                    version == null ? const _NoRulesYet() : _reader(version),
              ),
      ),
    );
  }

  Widget _reader(RulesVersion version) => Column(
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: ParchmentRod(),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ParchmentSheet(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (n) {
                _checkEnd(n.metrics);
                return false;
              },
              child: RulesReader(
                version: version,
                controller: _scroll,
                closing:
                    'Letto e compreso, entro a far parte del club e '
                    'mi impegno a rispettarne le regole.',
              ),
            ),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: ParchmentRod(),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_reachedEnd)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Scorri fino in fondo per poter accettare.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              FilledButton.icon(
                onPressed: _reachedEnd && !_saving
                    ? () => _accept(version)
                    : null,
                icon: const Icon(Icons.verified_rounded),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Ho letto e accetto'),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Nessuna versione pubblicata: si entra lo stesso. Il Direttivo (o chi ha chiesto di
/// farne parte) viene invitato a scrivere il regolamento d'ingresso.
class _NoRulesYet extends ConsumerStatefulWidget {
  const _NoRulesYet();

  @override
  ConsumerState<_NoRulesYet> createState() => _NoRulesYetState();
}

class _NoRulesYetState extends ConsumerState<_NoRulesYet> {
  bool _busy = false;

  Future<void> _enter(bool direttivo) async {
    setState(() => _busy = true);
    try {
      await ref.read(rulesRepositoryProvider).enter();
      if (!mounted) return;
      // Il router prosegue appena il profilo riletto ha il ruolo, senza aspettare il
      // tempo reale; in demo andiamo noi.
      ref.invalidate(profileProvider);
      if (AppConfig.isDemo) context.go(direttivo ? '/regolamento/scrivi' : '/');
    } catch (e) {
      if (!mounted) return;
      // Se nel frattempo una versione c'è (o è comparsa), la pagina la mostra.
      ref.invalidate(latestRulesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Ingresso non riuscito')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(profileProvider).value;
    final direttivo =
        p != null && (p.isDirettivo || p.requestedRole == ClubRole.direttivo);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.menu_book_rounded,
              size: 52,
              color: MilanacColors.gold,
            ),
            const SizedBox(height: 14),
            const Text(
              'REGOLAMENTO NON ANCORA PUBBLICATO',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: sportFont,
                fontSize: 20,
                letterSpacing: 1.5,
                color: MilanacColors.gold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              direttivo
                  ? 'Sei del Direttivo e sei tra i primi a entrare: il regolamento '
                        'd\'ingresso lo scrivi tu. Entra, aggiungi gli articoli e '
                        'pubblicalo: da quel momento ogni membro dovrà leggerlo per '
                        'almeno 2 minuti e accettarlo.'
                  : 'Il Direttivo non ha ancora scritto il regolamento d\'ingresso. '
                        'Entra pure: appena sarà pubblicato ti verrà chiesto di '
                        'leggerlo e accettarlo.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : () => _enter(direttivo),
              icon: Icon(
                direttivo ? Icons.edit_note_rounded : Icons.login_rounded,
              ),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(direttivo ? 'Entra e scrivilo' : 'Entra nel club'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
