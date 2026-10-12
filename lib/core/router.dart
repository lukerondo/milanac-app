import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/albo_doro/albo_doro_page.dart';
import '../features/auth/login_page.dart';
import '../features/auth/new_password_page.dart';
import '../features/auth/pending_page.dart';
import '../features/carte/carte_speciali_page.dart';
import '../features/chat/channel_page.dart';
import '../features/chat/chat_list_page.dart';
import '../features/club/club_page.dart';
import '../features/direttivo/direttivo_page.dart';
import '../features/formazione/formazione_page.dart';
import '../features/home/home_page.dart';
import '../features/impostazioni/impostazioni_page.dart';
import '../features/intro/intro_page.dart';
import '../features/intro/intro_state.dart';
import '../features/lavagna/board_page.dart';
import '../features/mondo/mondo_page.dart';
import '../features/partite/partite_page.dart';
import '../features/musica/musica_page.dart';
import '../features/presenze/presenze_page.dart';
import '../features/profilo/profilo_page.dart';
import '../features/regolamento/regolamento_page.dart';
import '../features/regolamento/rules_accept_page.dart';
import '../features/regolamento/rules_editor_page.dart';
import '../features/regolamento/rules_repository.dart';
import '../features/registrazione/registration_page.dart';
import '../features/risultati/match_detail_page.dart';
import '../features/rosa/rosa_page.dart';
import '../features/tattiche/tattiche_page.dart';
import '../shared/app_shell.dart';
import '../shared/offline_page.dart';
import '../shared/sections.dart';
import 'auth/profile.dart';
import 'auth/providers.dart';
import 'config.dart';

/// Pagine "di servizio" fuori dall'app: da lì, chi ha finito torna alla Home.
const gatePaths = {
  '/intro',
  '/login',
  '/attesa',
  '/offline',
  '/registrazione',
  '/regolamento/accetta',
  '/regolamento/scrivi',
  '/nuova-password',
};

/// Vecchi indirizzi (notifiche già inviate, link salvati) → dove stanno adesso.
const _movedPaths = {
  '/calendario': '/partite?scheda=calendario',
  '/risultati': '/partite?scheda=risultati',
  '/tornei': '/partite?scheda=tornei',
  '/carta': '/profilo',
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
    ref.listen(rulesWriteLaterProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/intro',
    refreshListenable: refresh,
    redirect: (context, state) {
      final moved = _movedPaths[state.uri.path];
      if (moved != null) return moved;
      final loc = state.matchedLocation;
      if (!ref.read(introDoneProvider)) {
        // Una notifica aperta ad app chiusa: ricordiamo dove andare dopo l'intro.
        if (loc != '/intro' && !gatePaths.contains(loc)) {
          ref.read(pendingRouteProvider.notifier).set(state.uri.toString());
        }
        return loc == '/intro' ? null : '/intro';
      }

      /// Dopo l'intro (o le porte) si torna alla Home, o alla sezione in sospeso.
      String? home() {
        final pending = ref.read(pendingRouteProvider);
        if (pending != null) {
          ref.read(pendingRouteProvider.notifier).set(null);
          return pending;
        }
        return '/';
      }

      // In demo non c'è login: intro e pagina di blocco rimandano alla Home;
      // accesso e registrazione restano visitabili per provarli.
      if (AppConfig.isDemo) {
        return loc == '/intro' || loc == '/attesa' ? home() : null;
      }

      final target = gateRedirect(
        loc: loc,
        session: ref.read(sessionProvider).whenData((s) => s != null),
        passwordRecovery: ref.read(passwordRecoveryProvider),
        profile: ref.read(profileProvider),
        rules: ref.read(latestRulesProvider).whenData((r) => r?.number),
        rulesWriteLater: ref.read(rulesWriteLaterProvider),
      );
      return target == goHome ? home() : target;
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
        path: '/regolamento/scrivi',
        builder: (_, _) => const RulesEditorPage(firstTime: true),
      ),
      GoRoute(
        path: '/nuova-password',
        builder: (_, _) => const NewPasswordPage(),
      ),
      GoRoute(path: '/offline', builder: (_, _) => const OfflinePage()),
      // Profilo e impostazioni: a tutto schermo, sopra le schede.
      GoRoute(path: '/profilo', builder: (_, _) => const ProfiloPage()),
      GoRoute(
        path: '/impostazioni',
        builder: (_, state) => ImpostazioniPage(
          initialSection: state.uri.queryParameters['sezione'],
        ),
      ),
      // Conversazione a schermo intero (anche dalle notifiche).
      GoRoute(
        path: '/chat/:slug',
        builder: (_, state) => ChannelPage(
          slug: state.pathParameters['slug']!,
          openVoice: state.uri.queryParameters['stanza'] == '1',
        ),
      ),
      // Lavagna tattica: nuova o uno schema salvato.
      GoRoute(path: '/lavagna', builder: (_, _) => const BoardPage()),
      GoRoute(
        path: '/lavagna/:id',
        builder: (_, state) =>
            SavedBoardPage(tacticId: state.pathParameters['id']!),
      ),
      // Le cinque schede della barra in basso: ognuna ricorda dove eri rimasto.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [_section('/', (_) => const HomePage())]),
          StatefulShellBranch(
            routes: [
              _section(
                '/presenze',
                (state) => PresenzePage(
                  initialDay: DateTime.tryParse(
                    state.uri.queryParameters['giorno'] ?? '',
                  ),
                  initialTab: state.uri.queryParameters['scheda'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _section(
                '/partite',
                (state) => PartitePage(
                  initialTab: state.uri.queryParameters['scheda'],
                ),
              ),
              _section(
                '/formazione',
                (_) => const FormazionePage(),
                actions: const [FormationPdfAction()],
              ),
              // Partita (dalla lista dei risultati e dalla notifica del risultato).
              GoRoute(
                path: '/partita/:id',
                builder: (_, state) =>
                    MatchDetailPage(matchId: state.pathParameters['id']!),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _section(
                '/chat',
                (_) => const ChatListPage(),
                actions: const [ChatSearchButton()],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _section('/club', (_) => const ClubPage()),
              _section(
                '/rosa',
                (_) => const RosaPage(),
                actions: const [RosaViewButton()],
              ),
              _section('/carte-speciali', (_) => const CarteSpecialiPage()),
              _section('/tattiche', (_) => const TattichePage()),
              _section(
                '/mondo',
                (state) =>
                    MondoPage(initialTab: state.uri.queryParameters['scheda']),
              ),
              _section('/albo-doro', (_) => const AlboDoroPage()),
              _section('/regolamento', (_) => const RegolamentoPage()),
              _section('/musica', (_) => const MusicaPage()),
              _section('/direttivo', (_) => const DirettivoPage()),
              // Presenze di stasera per il Direttivo (anche dalle notifiche).
              GoRoute(
                path: '/direttivo/stasera',
                builder: (_, _) => const TonightAttendancePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Una sezione dentro una scheda: barra in alto comune (con le azioni della pagina,
/// come nelle tavole) e passaggio in dissolvenza tra le pagine iniziali delle schede.
GoRoute _section(
  String path,
  Widget Function(GoRouterState state) page, {
  List<Widget> actions = const [],
}) => GoRoute(
  path: path,
  pageBuilder: (_, state) => CustomTransitionPage(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    child: SectionFrame(path: path, actions: actions, child: page(state)),
  ),
);

/// Risposta di [gateRedirect]: "torna alla Home (o alla sezione in sospeso)".
const goHome = '@home';

/// Le porte dell'app, in ordine: accesso, nuova password, profilo (o nessuna
/// connessione), registrazione, account attivo, regolamento, primo regolamento del
/// Direttivo, sezioni riservate. Restituisce dove andare, [goHome] o null (resta).
/// È una funzione pura: i test provano così anche la logica di produzione.
String? gateRedirect({
  required String loc,
  required AsyncValue<bool> session,
  required bool passwordRecovery,
  required AsyncValue<Profile?> profile,
  required AsyncValue<int?> rules,
  required bool rulesWriteLater,
}) {
  String? goTo(String target) => loc == target ? null : target;

  if (session.isLoading && !session.hasError) return null;
  if (!(session.value ?? false)) return goTo('/login');

  // Link "password dimenticata" appena aperto: prima la nuova password.
  if (passwordRecovery) return goTo('/nuova-password');

  // Profilo che non arriva (rete assente, server irraggiungibile): si aspetta sulla
  // pagina "Nessuna connessione", che riprova da sola. Non è un profilo mancante:
  // chi è già registrato non deve finire sulla registrazione.
  if (profile.hasError && !profile.hasValue) return goTo('/offline');
  if (profile.isLoading && !profile.hasError) return null;
  final p = profile.value;

  // 1) I tre passi della registrazione.
  if (p == null || !p.registrationCompleted) return goTo('/registrazione');
  // 2) Account rimosso o sospeso dal Direttivo.
  if (!p.active) return goTo('/attesa');
  // 3) Il regolamento, nella sua ultima versione. Chi non è ancora entrato nel club
  //    (ruolo "in attesa") deve accettarlo. Se il regolamento non si carica (rete) si
  //    va avanti con quello che si sa: la sua pagina gestisce errori e nuovi tentativi.
  if (rules.isLoading && !rules.hasError) return null;
  final latest = rules.value;
  if ((latest != null && p.rulesAcceptedVersion != latest) || !p.isApproved) {
    return goTo('/regolamento/accetta');
  }
  // 4) Nessuna versione pubblicata: il primo del Direttivo che entra la scrive (con
  //    "Più tardi" il promemoria resta nella Sala Direttivo, che riapre l'editor).
  final noRulesYet = rules.hasValue && latest == null;
  if (p.isDirettivo && noRulesYet && !rulesWriteLater) {
    return goTo('/regolamento/scrivi');
  }
  if (loc == '/regolamento/scrivi' && p.isDirettivo && noRulesYet) return null;

  // La Sala Direttivo (e le altre sezioni riservate) solo per il Direttivo.
  final reserved =
      appSections.any((s) => s.direttivoOnly && s.path == loc) ||
      loc.startsWith('/direttivo/');
  if (reserved && !p.isDirettivo) return '/';
  return gatePaths.contains(loc) ? goHome : null;
}
