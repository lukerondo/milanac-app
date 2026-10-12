import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart' show ContentWidth;
import '../../shared/async_view.dart';
import '../../shared/ui.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'chat_repository.dart';
import 'chat_widgets.dart';

/// Azione "Cerca nei messaggi" della barra in alto della scheda Chat (tavola 12).
class ChatSearchButton extends StatelessWidget {
  const ChatSearchButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Cerca nei messaggi',
    icon: const Icon(Icons.search_rounded, size: 22),
    onPressed: () => showChatSearch(context),
  );
}

/// Apre la ricerca nei messaggi a schermo intero, sopra le schede.
Future<void> showChatSearch(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'cerca-nei-messaggi'),
        builder: (_) => const ChatSearchPage(),
      ),
    );

/// Ricerca nei messaggi dei canali che si vedono: canale, autore, data e il testo
/// con la parola evidenziata; un tocco apre il canale.
class ChatSearchPage extends ConsumerStatefulWidget {
  const ChatSearchPage({super.key});

  @override
  ConsumerState<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends ConsumerState<ChatSearchPage> {
  final _field = TextEditingController();
  Timer? _typing;

  /// La parola cercata (si aggiorna poco dopo che si smette di scrivere).
  String _query = '';

  @override
  void dispose() {
    _typing?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () => _search(text));
  }

  void _search(String text) {
    _typing?.cancel();
    if (mounted) setState(() => _query = text.trim());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Indietro',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: const Text('CERCA NEI MESSAGGI'),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: ColoredBox(
          color: AppPalette.dark.border,
          child: const SizedBox(height: 1, width: double.infinity),
        ),
      ),
      flexibleSpace: const Align(
        alignment: Alignment.topCenter,
        child: GoldRule(),
      ),
    ),
    body: ContentWidth(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: ValueListenableBuilder(
              valueListenable: _field,
              builder: (context, value, _) => TextField(
                controller: _field,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Parola o frase da cercare',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Cancella',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _field.clear();
                            _search('');
                          },
                        ),
                ),
                onChanged: _changed,
                onSubmitted: _search,
              ),
            ),
          ),
          Expanded(child: _results()),
        ],
      ),
    ),
  );

  Widget _results() {
    final q = _query;
    if (q.length < chatSearchMinLength) {
      return const _SearchNote(
        icon: Icons.manage_search_rounded,
        text:
            'Scrivi almeno 2 lettere: cerco nei messaggi dei canali che vedi.',
      );
    }
    final channels = {
      for (final c in ref.watch(channelsProvider).value ?? const <Channel>[])
        c.id: c,
    };
    final me = ref.watch(currentUserIdProvider);
    final members = {
      for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
        m.id: m.displayName,
    };
    String nameOf(String? id) => id == null
        ? 'MILANAC'
        : id == me
        ? 'Tu'
        : members[id] ?? 'Ex membro';
    final provider = chatSearchProvider(q);
    return AsyncView<List<ChatMessage>>(
      value: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      action: 'Ricerca non riuscita',
      data: (found) {
        // Solo i canali che si vedono (le regole del database fanno già così).
        final shown = [
          for (final m in found)
            if (channels.containsKey(m.channelId)) m,
        ];
        if (shown.isEmpty) {
          return _SearchNote(
            icon: Icons.search_off_rounded,
            text: 'Nessun messaggio con «$q».',
          );
        }
        final count = shown.length == 1
            ? '1 messaggio'
            : '${shown.length} messaggi';
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            SectionLabel(
              found.length >= chatSearchLimit ? '$count, i più recenti' : count,
            ),
            const SizedBox(height: 10),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, m) in shown.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 62),
                    _SearchResult(
                      message: m,
                      channel: channels[m.channelId]!,
                      author: nameOf(m.authorId),
                      query: q,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Un messaggio trovato: canale e data, autore, il testo con la parola in oro.
class _SearchResult extends StatelessWidget {
  const _SearchResult({
    required this.message,
    required this.channel,
    required this.author,
    required this.query,
  });
  final ChatMessage message;
  final Channel channel;
  final String author;
  final String query;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: () => context.push('/chat/${channel.slug}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChannelTile(channel: channel, size: 36, radius: 11),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: p.accentText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        chatWhen(message.createdAt, withTime: true),
                        style: TextStyle(fontSize: 13, color: p.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: highlightMatches(
                        searchSnippet(message.body ?? '', query),
                        query,
                        hit: TextStyle(
                          color: p.accentText,
                          fontWeight: FontWeight.w700,
                          backgroundColor: p.accentTint,
                        ),
                      ),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Indicazione al centro (prima di cercare, nessun risultato).
class _SearchNote extends StatelessWidget {
  const _SearchNote({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: p.textMuted),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
