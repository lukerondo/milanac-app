import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/ui.dart';
import '../../shared/wide_layout.dart';
import '../musica/musica_page.dart';
import '../musica/soundtrack.dart';
import 'chat_list_page.dart';

/// La scheda Chat: l'elenco dei canali. Sui telefoni un tocco apre la conversazione a
/// schermo intero; sugli schermi larghi elenco e conversazione stanno fianco a fianco
/// ([ChatDesktop]).
class ChatSection extends StatelessWidget {
  const ChatSection({super.key});

  @override
  Widget build(BuildContext context) => isWideLayout(context)
      ? const ChatDesktop()
      : const SectionFrame(
          path: '/chat',
          actions: [ChatSearchButton()],
          child: ChatListPage(),
        );
}

/// Chat a due colonne (schermi larghi): a sinistra l'elenco dei canali, con la
/// ricerca; a destra la conversazione aperta, oppure l'invito a sceglierne una.
class ChatDesktop extends ConsumerWidget {
  const ChatDesktop({super.key, this.selectedSlug, this.conversation});

  /// Il canale aperto a destra (la sua riga è evidenziata nell'elenco).
  final String? selectedSlug;

  /// La conversazione aperta; senza, l'invito a scegliere un canale.
  final Widget? conversation;

  /// Larghezza della colonna con l'elenco dei canali.
  static const listWidth = 340.0;

  /// Altezza delle barre in alto delle due colonne (quella della conversazione).
  static const barHeight = 60.0;

  /// Larghezza massima della colonna dei messaggi dentro la conversazione.
  static const conversationWidth = 880.0;

  void _open(BuildContext context, String slug) {
    if (slug == selectedSlug) return;
    final path = '/chat/$slug';
    // La prima conversazione si apre sopra le schede, che restano com'erano; le
    // successive ne prendono il posto (indietro riporta sempre all'elenco).
    if (conversation == null) {
      context.push(path);
    } else {
      context.pushReplacement(path);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: listWidth,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: barHeight,
              titleSpacing: 24,
              title: const Text('CHAT'),
              actions: [
                ChatSearchButton(
                  onOpen: (slug) {
                    if (context.mounted) _open(context, slug);
                  },
                ),
                // Il muto della colonna sonora resta sempre in alto (se c'è un brano).
                if (ref.watch(soundtrackProvider.select((s) => s.hasTrack)))
                  const SoundtrackButton(),
                const SizedBox(width: 4),
              ],
              bottom: const _BarBorder(),
              flexibleSpace: const Align(
                alignment: Alignment.topCenter,
                child: GoldRule(),
              ),
            ),
            body: ChatListPage(
              selectedSlug: selectedSlug,
              onOpen: (c) => _open(context, c.slug),
            ),
          ),
        ),
        const _ColumnDivider(),
        Expanded(
          // Dentro la colonna la conversazione si regola sulla propria larghezza,
          // non su quella della finestra (le bolle, per esempio).
          child: LayoutBuilder(
            builder: (context, constraints) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  size: Size(constraints.maxWidth, media.size.height),
                ),
                child: conversation ?? const _NoConversation(),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Il filo scuro sotto le barre in alto (sempre scure, come nelle sezioni).
class _BarBorder extends StatelessWidget implements PreferredSizeWidget {
  const _BarBorder();

  @override
  Size get preferredSize => const Size.fromHeight(1);

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppPalette.dark.border,
    child: const SizedBox(height: 1, width: double.infinity),
  );
}

/// Il filo tra le due colonne: scuro accanto alle barre in alto, poi del colore dei
/// bordi del tema.
class _ColumnDivider extends StatelessWidget {
  const _ColumnDivider();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 1,
    child: Column(
      children: [
        ColoredBox(
          color: AppPalette.dark.border,
          child: SizedBox(
            width: 1,
            height:
                MediaQuery.paddingOf(context).top + ChatDesktop.barHeight + 1,
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: context.pal.border,
            child: const SizedBox(width: 1),
          ),
        ),
      ],
    ),
  );
}

/// Nessuna conversazione aperta: l'invito a sceglierne una dall'elenco.
class _NoConversation extends StatelessWidget {
  const _NoConversation();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: ChatDesktop.barHeight,
        bottom: const _BarBorder(),
        flexibleSpace: const Align(
          alignment: Alignment.topCenter,
          child: GoldRule(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconTile(Icons.chat_bubble_outline_rounded, size: 56),
              const SizedBox(height: 16),
              Text(
                'Scegli una conversazione',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Apri un canale dall\'elenco: la conversazione compare qui accanto.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
