import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/albo_doro/albo_doro_page.dart';
import '../features/auth/login_page.dart';
import '../features/auth/new_password_page.dart';
import '../features/auth/pending_page.dart';
import '../features/calendario/calendario_page.dart';
import '../features/carta/carta_page.dart';
import '../features/carte/carte_speciali_page.dart';
import '../features/chat/channel_page.dart';
import '../features/chat/chat_list_page.dart';
import '../features/common/coming_soon_page.dart';
import '../features/direttivo/direttivo_page.dart';
import '../features/formazione/formazione_page.dart';
import '../features/home/home_page.dart';
import '../features/impostazioni/impostazioni_page.dart';
import '../features/intro/intro_page.dart';
import '../features/intro/intro_state.dart';
import '../features/lavagna/board_page.dart';
import '../features/mondo/mondo_page.dart';
import '../features/musica/musica_page.dart';
import '../features/presenze/presenze_page.dart';
import '../features/regolamento/regolamento_page.dart';
import '../features/regolamento/rules_accept_page.dart';
import '../features/regolamento/rules_repository.dart';
import '../features/registrazione/registration_page.dart';
import '../features/risultati/match_detail_page.dart';
import '../features/risultati/risultati_page.dart';
import '../features/rosa/rosa_page.dart';
import '../features/tattiche/tattiche_page.dart';
import '../features/tornei/tornei_page.dart';
import '../shared/app_shell.dart';
import '../shared/sections.dart';
import 'auth/providers.dart';
import 'config.dart';

/// Pagine "di servizio" fuori dall'app: da lì, chi ha finito torna alla Home.
const gatePaths = {
  '/intro',
  '/login',
  '/attesa',
  '/registrazione',
  '/regolamento/accetta',
  '/nuova-password',
};

/// Sezione chiesta (es. da una notifica) mentre l'intro era ancora in corso:
/// viene aperta appena l'intro finisce.
final pendingRouteProvider = NotifierProvider<PendingRoute, String?>(
  PendingRoute.new,
);

class PendingRoute extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? route) => state = route;
}

/// Fa ricalcolare i redirect al router quando cambiano intro, sessione, profilo,
/// recupero password o versione del regolamento.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(introDoneProvider, (_, _) => notifyListeners());
    ref.listen(sessionProvider, (_, _) => notifyListeners());
    ref.listen(profileProvider, (_, _) => notifyListeners());
    ref.listen(passwordRecoveryProvider, (_, _) => notifyListeners());
    ref.listen(latestRulesProvider, (_, _) => notifyListeners());
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
        // Una notifica aperta ad app chiusa: ricordiamo dove andare dopo l'intro.
        if (loc != '/intro' && !gatePaths.contains(loc)) {
          ref.read(pendingRouteProvider.notifier).set(state.uri.toString());
        }
        return loc == '/intro' ? null : '/intro';
      }

      String? goTo(String target) => loc == target ? null : target;

      /// Dopo l'intro (o le porte) si torna alla Home, o alla sezione in sospeso.
      String? home() {
        final pending = ref.read(pendingRouteProvider);
        if (pending != null) {
          ref.read(pendingRouteProvider.notifier).set(null);
          return pending;
        }
        return '/';
      }

      // La Sala Direttivo (e le altre sezioni riservate) solo per il Direttivo.
      final reserved =
          appSections.any((s) => s.direttivoOnly && s.path == loc) ||
          loc.startsWith('/direttivo/');

      // In demo non c'è login: intro e pagina di blocco rimandano alla Home;
      // accesso e registrazione restano visitabili per provarli.
      if (AppConfig.isDemo) {
        return loc == '/intro' || loc == '/attesa' ? home() : null;
      }

      final session = ref.read(sessionProvider);
      if (session.isLoading) return null;
      if (session.value == null) return goTo('/login');

      // Link "password dimenticata" appena aperto: prima la nuova password.
      if (ref.read(passwordRecoveryProvider)) return goTo('/nuova-password');

      final profile = ref.read(profileProvider);
      if (profile.isLoading) return null;
      final p = profile.value;

      // 1) I tre passi della registrazione.
      if (p == null || !p.registrationCompleted) return goTo('/registrazione');
      // 2) Account rimosso o sospeso dal Direttivo.
      if (!p.active) return goTo('/attesa');
      // 3) Il regolamento, nella sua ultima versione. Chi non è ancora entrato nel club
      //    (ruolo "in attesa") deve accettarlo: la pagina del regolamento gestisce da sola
      //    caricamento ed errori, così un problema di rete non lo manda alla pagina sbagliata.
      final rules = ref.read(latestRulesProvider);
      if (rules.isLoading) return null;
      final latest = rules.value?.number;
      if ((latest != null && p.rulesAcceptedVersion != latest) || !p.isApproved) {
        return goTo('/regolamento/accetta');
      }

      if (reserved && !p.isDirettivo) return '/';
      return gatePaths.contains(loc) ? home() : null;
    },
    routes: [
      GoRoute(path: '/intro', builder: (_, _) => const IntroPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/attesa', builder: (_, _) => const PendingPage()),
      GoRoute(
        path: '/registrazione',
        builder: (_, state) => RegistrationPage(
          initialStep:
              int.tryParse(state.uri.queryParameters['passo'] ?? '') ?? 1,
        ),
      ),
      GoRoute(
        path: '/regolamento/accetta',
        builder: (_, _) => const RulesAcceptPage(),
      ),
      GoRoute(
        path: '/nuova-password',
        builder: (_, _) => const NewPasswordPage(),
      ),
      GoRoute(
        path: '/impostazioni',
        builder: (_, _) => const ImpostazioniPage(),
      ),
      // Presenze di stasera per il Direttivo (anche dalle notifiche).
      GoRoute(
        path: '/direttivo/stasera',
        builder: (_, _) => const TonightAttendancePage(),
      ),
      // Partita (dalla notifica del risultato).
      GoRoute(
        path: '/partita/:id',
        builder: (_, state) =>
            MatchDetailPage(matchId: state.pathParameters['id']!),
      ),
      // Conversazione a schermo intero (anche dalle notifiche).
      GoRoute(
        path: '/chat/:slug',
        builder: (_, state) => ChannelPage(slug: state.pathParameters['slug']!),
      ),
      // Lavagna tattica: nuova o uno schema salvato.
      GoRoute(path: '/lavagna', builder: (_, _) => const BoardPage()),
      GoRoute(
        path: '/lavagna/:id',
        builder: (_, state) =>
            SavedBoardPage(tacticId: state.pathParameters['id']!),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(path: state.matchedLocation, child: child),
        routes: [
          for (final s in appSections)
            GoRoute(
              path: s.path,
              pageBuilder: (_, state) => CustomTransitionPage(
                key: state.pageKey,
                transitionDuration: const Duration(milliseconds: 220),
                transitionsBuilder: (_, animation, _, child) =>
                    FadeTransition(opacity: animation, child: child),
                child: switch (s.path) {
                  '/' => const HomePage(),
                  '/mondo' => MondoPage(
                    initialTab: state.uri.queryParameters['scheda'],
                  ),
                  '/rosa' => const RosaPage(),
                  '/regolamento' => const RegolamentoPage(),
                  '/presenze' => PresenzePage(
                    initialDay: DateTime.tryParse(
                      state.uri.queryParameters['giorno'] ?? '',
                    ),
                    initialTab: state.uri.queryParameters['scheda'],
                  ),
                  '/calendario' => const CalendarioPage(),
                  '/risultati' => const RisultatiPage(),
                  '/formazione' => const FormazionePage(),
                  '/albo-doro' => const AlboDoroPage(),
                  '/musica' => const MusicaPage(),
                  '/carta' => const MyCardPage(),
                  '/carte-speciali' => const CarteSpecialiPage(),
                  '/tattiche' => const TattichePage(),
                  '/chat' => const ChatListPage(),
                  '/tornei' => const TorneiPage(),
                  '/direttivo' => const DirettivoPage(),
                  _ => ComingSoonPage(path: s.path),
                },
              ),
            ),
        ],
      ),
    ],
  );
});
