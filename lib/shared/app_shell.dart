import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/profile.dart';
import '../core/auth/providers.dart';
import '../core/teams.dart';
import '../core/theme.dart';
import '../features/chat/chat_repository.dart';
import '../features/musica/musica_page.dart';
import '../features/musica/soundtrack.dart';
import '../features/rosa/rosa_repository.dart';
import '../features/walkout/celebrations.dart';
import 'member_photo.dart';
import 'sections.dart';
import 'side_menu.dart';
import 'ui.dart';
import 'wide_layout.dart';

/// Nome del club in alto nella Home e nel Club: dipende dalla squadra del membro
/// (chi è solo in MILANAC FUTURO vede il nome della sua squadra).
String clubTitleFor(Profile? profile) {
  final teams = profile?.teams ?? const {Team.milanac};
  return teams.contains(Team.milanac)
      ? 'MILANAC PRO CLUB'
      : 'MILANAC FUTURO PRO CLUB';
}

/// Struttura comune: la sezione sopra e le cinque schede sempre visibili in basso;
/// sugli schermi larghi le schede stanno nel menu laterale ([SideMenu]).
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(chatUnreadProvider);
    final wide = isWideLayout(context);
    Widget icon(MainTab t, IconData data) => t == MainTab.chat && unread > 0
        ? Badge(label: Text(unread > 99 ? '99+' : '$unread'), child: Icon(data))
        : Icon(data);
    // Toccare la scheda già aperta riporta alla sua pagina iniziale.
    void open(int i) =>
        shell.goBranch(i, initialLocation: i == shell.currentIndex);
    return PopScope(
      // Indietro da un'altra scheda riporta alla Home prima di chiudere l'app.
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && shell.currentIndex != 0) shell.goBranch(0);
      },
      child: WideSnackBars(
        child: Scaffold(
          body: Celebrations(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  SideMenu(
                    current: MainTab.values[shell.currentIndex],
                    onSelect: (t) => open(t.index),
                  ),
                // La chiave tiene ferme le schede (e quello che c'è dentro) quando la
                // finestra si allarga o si stringe e il menu compare o sparisce.
                Expanded(
                  key: const ValueKey('schede'),
                  // Il margine del bordo sinistro dello schermo (tacca, angoli) lo
                  // prende già il menu.
                  child: MediaQuery.removePadding(
                    context: context,
                    removeLeft: wide,
                    child: shell,
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: open,
                  destinations: [
                    for (final t in MainTab.values)
                      NavigationDestination(
                        icon: icon(t, t.icon),
                        selectedIcon: icon(t, t.selectedIcon),
                        label: t.label,
                        tooltip: t == MainTab.chat && unread > 0
                            ? 'Chat, $unread messaggi nuovi'
                            : t.label,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Cornice di una sezione: barra in alto (stemma o freccia indietro, titolo, musica,
/// la tua foto) e contenuto a larghezza leggibile anche sui tablet. Sugli schermi
/// larghi lo stemma, il nome del club e la tua foto stanno nel menu laterale.
class SectionFrame extends ConsumerWidget {
  const SectionFrame({
    super.key,
    required this.path,
    required this.child,
    this.actions = const [],
    this.maxWidth = ContentWidth.maxWidth,
  });

  /// Sezione di [appSections] (es. "/rosa").
  final String path;
  final Widget child;
  final List<Widget> actions;

  /// Larghezza massima del contenuto (le griglie di carte ne usano di più).
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = sectionFor(path);
    final parent = section.parent;
    final router = GoRouter.of(context);
    final canPop = router.canPop();
    final isTabRoot = parent == null;
    final wide = isWideLayout(context);
    // Il nome del club è il titolo della Home (su schermo largo è già nel menu).
    final title = section.tab == MainTab.home && isTabRoot && !wide
        ? clubTitleFor(ref.watch(profileProvider).value)
        : section.title.toUpperCase();
    // La Sala Direttivo ha la barra d'oro pieno (tavola 26).
    final gold = path == '/direttivo';
    return PopScope(
      // Una sottosezione aperta direttamente (es. da una notifica): indietro
      // porta alla sua sezione, non fuori dall'app.
      canPop: isTabRoot || canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && parent != null) context.go(parent);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: gold ? MilanacColors.gold : null,
          foregroundColor: gold ? MilanacColors.ink : null,
          titleTextStyle: gold
              ? Theme.of(context).appBarTheme.titleTextStyle
                    ?.copyWith(color: MilanacColors.ink)
              : null,
          systemOverlayStyle: gold ? SystemUiOverlayStyle.dark : null,
          automaticallyImplyLeading: false,
          leading: isTabRoot
              ? wide
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Image.asset('assets/images/stemma_256.png'),
                      )
              : IconButton(
                  tooltip: 'Indietro',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => canPop ? context.pop() : context.go(parent),
                ),
          leadingWidth: isTabRoot ? 52 : 56,
          titleSpacing: isTabRoot && wide ? 24 : null,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            ...actions,
            // Il muto della colonna sonora resta sempre in alto (se c'è un brano).
            if (ref.watch(soundtrackProvider.select((s) => s.hasTrack)))
              const SoundtrackButton(),
            if (section.tab == MainTab.home && isTabRoot)
              IconButton(
                tooltip: 'Notifiche',
                icon: const Icon(Icons.notifications_none_rounded),
                onPressed: () =>
                    context.push('/impostazioni?sezione=notifiche'),
              ),
            if (isTabRoot && !wide) const ProfileButton(),
            if (wide) const SizedBox(width: 8),
          ],
          bottom: gold
              ? null
              : const PreferredSize(
                  preferredSize: Size.fromHeight(1),
                  child: ColoredBox(
                    color: Color(0xFF2B2B2F),
                    child: SizedBox(height: 1, width: double.infinity),
                  ),
                ),
          flexibleSpace: gold
              ? null
              : const Align(alignment: Alignment.topCenter, child: GoldRule()),
        ),
        body: ContentWidth(maxWidth: wide ? maxWidth : null, child: child),
      ),
    );
  }
}

/// La tua foto in alto a destra: apre il profilo con la carta e le impostazioni.
class ProfileButton extends ConsumerWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final member = me == null
        ? null
        : ref
              .watch(rosaProvider)
              .value
              ?.where((m) => m.id == me.id)
              .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        tooltip: 'Il tuo profilo',
        onPressed: () => context.push('/profilo'),
        icon: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFB8952F),
          ),
          child: member == null
              ? const CircleAvatar(
                  radius: 15,
                  backgroundColor: MilanacColors.surfaceHigh,
                  child: Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: MilanacColors.ivoryMuted,
                  ),
                )
              : MemberAvatar(member: member, radius: 15),
        ),
      ),
    );
  }
}

/// Larghezza massima del contenuto: sui tablet e sui computer le sezioni restano una
/// colonna leggibile al centro; sui telefoni non cambia nulla.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, double? maxWidth})
    : width = maxWidth ?? ContentWidth.maxWidth;
  final Widget child;

  /// Larghezza massima di questo contenuto (di solito [maxWidth]).
  final double width;

  static const maxWidth = 720.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth <= width) return child;
      return Center(
        child: SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: child,
        ),
      );
    },
  );
}

/// Come [ContentWidth], ma solo sugli schermi larghi: per le pagine a schermo intero
/// che sui telefoni e sui tablet occupano tutta la larghezza.
class WideContentWidth extends StatelessWidget {
  const WideContentWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ContentWidth(
    maxWidth: isWideLayout(context) ? null : double.infinity,
    child: child,
  );
}
