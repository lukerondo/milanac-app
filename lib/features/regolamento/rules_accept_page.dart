import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/push/device_tokens.dart';
import '../../core/theme.dart';
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
  Timer? _timer;
  bool _timeOk = false;
  bool _reachedEnd = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(rulesReadingTime, () {
      if (mounted) setState(() => _timeOk = true);
    });
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_reachedEnd || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 24) {
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
      HapticFeedback.mediumImpact();
      messenger.hideCurrentMaterialBanner();
      // Con Supabase il profilo si aggiorna da solo e il router apre la Home.
      if (AppConfig.isDemo && mounted) context.go('/');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Accettazione non riuscita: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                tooltip: 'Esci',
                icon: const Icon(Icons.logout_rounded),
                onPressed: () => logout(ref),
              ),
          ],
        ),
        body: rules.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 40,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 8),
                  const Text('Impossibile caricare il regolamento.'),
                  TextButton(
                    onPressed: () => ref.invalidate(latestRulesProvider),
                    child: const Text('Riprova'),
                  ),
                ],
              ),
            ),
          ),
          data: (version) => version == null
              ? const Center(child: Text('Nessun regolamento pubblicato.'))
              : Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: ParchmentRod(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ParchmentSheet(
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
                ),
        ),
      ),
    );
  }
}
