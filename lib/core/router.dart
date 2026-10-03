import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/calendario/calendario_page.dart';
import '../features/auth/pending_page.dart';
import '../features/common/coming_soon_page.dart';
import '../features/formazione/formazione_page.dart';
import '../features/intro/intro_page.dart';
import '../features/intro/intro_state.dart';
import '../features/news/news_page.dart';
import '../features/presenze/presenze_page.dart';
import '../features/regolamento/regolamento_page.dart';
import '../features/risultati/risultati_page.dart';
import '../features/rosa/rosa_page.dart';
import '../shared/app_shell.dart';
import '../shared/sections.dart';
import 'auth/providers.dart';
import 'config.dart';

/// Fa ricalcolare i redirect al router quando cambiano intro, sessione o profilo.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(introDoneProvider, (_, _) => notifyListeners());
    ref.listen(sessionProvider, (_, _) => notifyListeners());
    ref.listen(profileProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/intro',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (!ref.read(introDoneProvider)) {
        return loc == '/intro' ? null : '/intro';
      }

      const gates = {'/intro', '/login', '/attesa'};
      String? goTo(String target) => loc == target ? null : target;

      if (AppConfig.isDemo) return gates.contains(loc) ? '/' : null;

      final session = ref.read(sessionProvider);
      if (session.isLoading) return null;
      if (session.value == null) return goTo('/login');

      final profile = ref.read(profileProvider);
      if (profile.isLoading) return null;
      if (profile.value?.isApproved != true) return goTo('/attesa');

      return gates.contains(loc) ? '/' : null;
    },
    routes: [
      GoRoute(path: '/intro', builder: (_, _) => const IntroPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/attesa', builder: (_, _) => const PendingPage()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(path: state.matchedLocation, child: child),
        routes: [
          for (final s in appSections)
            GoRoute(
              path: s.path,
              pageBuilder: (_, _) => NoTransitionPage(
                child: switch (s.path) {
                  '/' => const NewsPage(),
                  '/rosa' => const RosaPage(),
                  '/regolamento' => const RegolamentoPage(),
                  '/presenze' => const PresenzePage(),
                  '/calendario' => const CalendarioPage(),
                  '/risultati' => const RisultatiPage(),
                  '/formazione' => const FormazionePage(),
                  _ => ComingSoonPage(path: s.path),
                },
              ),
            ),
        ],
      ),
    ],
  );
});
