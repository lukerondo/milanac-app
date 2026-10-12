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
import '../../shared/ui.dart';
import '../auth/gate_ui.dart';
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

  /// Il messenger su cui è stato mostrato l'avviso "Servono 2 minuti" (null = mai).
  ScaffoldMessengerState? _bannerMessenger;

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    _scroll.dispose();
    // L'avviso sta nel messenger dell'app, sopra tutte le pagine: se questa se ne va
    // (uscita dall'account, regolamento accettato) non deve restare su quella dopo.
    // Si toglie dopo il disegno: mentre si smonta la pagina il messenger non si
    // aggiorna. Gli avvisi di questo tipo li mostra solo questa pagina.
    final messenger = _bannerMessenger;
    if (messenger != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!messenger.mounted) return;
        messenger
          ..clearMaterialBanners()
          ..removeCurrentMaterialBanner();
      });
    }
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
      final p = context.pal;
      messenger.hideCurrentMaterialBanner();
      _bannerMessenger = messenger;
      messenger.showMaterialBanner(
        MaterialBanner(
          backgroundColor: p.warningBg,
          dividerColor: p.border,
          leading: Icon(Icons.hourglass_top_rounded, color: p.warning),
          content: Text(
            'Servono 2 minuti di lettura: continua a leggere il regolamento e riprova.',
            style: TextStyle(color: p.text, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: messenger.hideCurrentMaterialBanner,
              style: TextButton.styleFrom(foregroundColor: p.accentText),
              child: const Text('OK'),
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
    final approved = ref.watch(
      profileProvider.select((p) => p.value?.isApproved ?? false),
    );
    return Scaffold(
      appBar: gateAppBar(
        title: 'REGOLAMENTO',
        automaticallyImplyLeading: false,
        leadingWidth: 54,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Image.asset('assets/images/stemma_256.png', width: 30),
        ),
        actions: [
          if (!AppConfig.isDemo)
            IconButton(
              tooltip: 'Esci dall\'account',
              icon: const Icon(Icons.logout_rounded),
              color: AppPalette.dark.textSecondary,
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
              data: (version) => version == null
                  ? const _NoRulesYet()
                  : _reader(version, approved: approved),
            ),
    );
  }

  /// Quanto è stato letto (0-1): la barra sottile nella fascia in alto.
  double get _readFraction {
    if (_reachedEnd || !_scroll.hasClients) return _reachedEnd ? 1 : 0;
    final pos = _scroll.position;
    if (!pos.hasContentDimensions || pos.maxScrollExtent <= 0) return 1;
    return (pos.pixels / pos.maxScrollExtent).clamp(0, 1);
  }

  Widget _reader(RulesVersion version, {required bool approved}) {
    final p = context.pal;
    return Column(
      children: [
        SubHeader(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListenableBuilder(
                listenable: _scroll,
                builder: (context, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _readFraction,
                    minHeight: 3,
                    backgroundColor: p.border,
                    color: p.accentText,
                    semanticsLabel: 'Regolamento letto',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                rulesVersionLabel(version),
                style: TextStyle(color: p.textMuted, fontSize: 14),
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (n) {
              _checkEnd(n.metrics);
              return false;
            },
            child: RulesReader(
              version: version,
              controller: _scroll,
              showVersion: false,
              intro: approved
                  ? 'È uscita una nuova versione: leggila fino in fondo e '
                        'accettala per continuare.'
                  : 'Leggilo fino in fondo: per entrare nel club devi accettarlo.',
              closing:
                  'Letto e compreso, entro a far parte del club e mi impegno a '
                  'rispettarne le regole.',
            ),
          ),
        ),
        BottomActionBar(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_reachedEnd) ...[
                Text(
                  'Scorri fino in fondo per poter accettare',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 8),
              ],
              PrimaryButton(
                label: 'Ho letto e accetto',
                fontSize: 16,
                busy: _saving,
                onPressed: _reachedEnd ? () => _accept(version) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
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
    final pal = context.pal;
    final direttivo =
        p != null && (p.isDirettivo || p.requestedRole == ClubRole.direttivo);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: IconTile(Icons.menu_book_rounded, size: 64)),
              const SizedBox(height: 16),
              const Center(
                child: GateTitle(
                  'Regolamento non ancora pubblicato',
                  size: 22,
                  gold: true,
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
                style: TextStyle(
                  color: pal.textSecondary,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: direttivo ? 'Entra e scrivilo' : 'Entra nel club',
                fontSize: 16,
                busy: _busy,
                onPressed: () => _enter(direttivo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
