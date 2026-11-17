import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_flags.dart';
import '../../core/theme.dart';

/// Un gruppo di emoji del selettore.
class EmojiCategory {
  const EmojiCategory(this.label, this.icon, this.emojis);
  final String label;
  final IconData icon;
  final List<String> emojis;
}

/// Le emoji del selettore: una scelta per le chat di un club di calcio, non tutto
/// l'elenco Unicode. Solo emoji che anche i telefoni di qualche anno fa sanno disegnare
/// (niente novità degli ultimi anni: comparirebbero come quadratini vuoti).
const emojiCategories = [
  EmojiCategory('Faccine', Icons.emoji_emotions_rounded, [
    '😀',
    '😃',
    '😄',
    '😁',
    '😆',
    '😅',
    '🤣',
    '😂',
    '🙂',
    '🙃',
    '😉',
    '😊',
    '😇',
    '🥰',
    '😍',
    '🤩',
    '😘',
    '😋',
    '😛',
    '😜',
    '🤪',
    '😝',
    '🤑',
    '🤗',
    '🤭',
    '🤫',
    '🤔',
    '🤐',
    '🤨',
    '😐',
    '😑',
    '😶',
    '😏',
    '😒',
    '🙄',
    '😬',
    '🤥',
    '😌',
    '😔',
    '😪',
    '🤤',
    '😴',
    '😷',
    '🤒',
    '🤕',
    '🤢',
    '🤮',
    '🥵',
    '🥶',
    '🥴',
    '😵',
    '🤯',
    '🤠',
    '🥳',
    '😎',
    '🤓',
    '🧐',
    '😕',
    '😟',
    '🙁',
    '😮',
    '😯',
    '😲',
    '😳',
    '🥺',
    '😨',
    '😰',
    '😥',
    '😢',
    '😭',
    '😱',
    '😖',
    '😣',
    '😞',
    '😓',
    '😩',
    '😫',
    '🥱',
    '😤',
    '😡',
    '😠',
    '🤬',
    '😈',
    '👿',
    '💀',
    '💩',
    '🤡',
    '👻',
    '👽',
    '🤖',
  ]),
  EmojiCategory('Gesti', Icons.thumb_up_rounded, [
    '👍',
    '👎',
    '👏',
    '🙌',
    '🙏',
    '🤝',
    '👊',
    '✊',
    '🤛',
    '🤜',
    '🤞',
    '✌️',
    '🤟',
    '🤘',
    '👌',
    '🤌',
    '🤏',
    '👈',
    '👉',
    '👆',
    '👇',
    '☝️',
    '✋',
    '🤚',
    '🖐️',
    '🖖',
    '👋',
    '🤙',
    '💪',
    '🦾',
    '✍️',
    '🤳',
    '👀',
    '🧠',
    '🤷',
    '🤦',
    '🙋',
    '🙅',
    '🙆',
    '💁',
  ]),
  EmojiCategory('Calcio e sport', Icons.sports_soccer_rounded, [
    '⚽',
    '🥅',
    '🏟️',
    '🏆',
    '🥇',
    '🥈',
    '🥉',
    '🏅',
    '🎖️',
    '🟥',
    '🟨',
    '🧤',
    '👟',
    '🎽',
    '🏃',
    '🤾',
    '🤸',
    '🏋️',
    '🎯',
    '🎮',
    '🕹️',
    '🎧',
    '🎤',
    '📣',
    '📢',
    '⏱️',
    '⏰',
    '🚩',
    '🏁',
    '🏀',
    '🏈',
    '🎾',
    '🏐',
    '🏉',
    '🎱',
    '🏓',
    '🥊',
    '♟️',
    '🎲',
  ]),
  EmojiCategory('Cuori e simboli', Icons.favorite_rounded, [
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '🖤',
    '🤍',
    '🤎',
    '💔',
    '❣️',
    '💕',
    '💞',
    '💓',
    '💗',
    '💖',
    '💘',
    '💝',
    '🔥',
    '✨',
    '⭐',
    '🌟',
    '💫',
    '💥',
    '💯',
    '✅',
    '❌',
    '❗',
    '❓',
    '⚠️',
    '🚫',
    '🔴',
    '⚫',
    '⚪',
    '🟢',
    '🔵',
    '🟡',
    '🔝',
    '🆗',
    '🆕',
    '💤',
    '💢',
    '💦',
    '💨',
    '🎵',
    '🎶',
    '➕',
    '➖',
  ]),
  EmojiCategory('Festa e cibo', Icons.celebration_rounded, [
    '🎉',
    '🎊',
    '🎂',
    '🍾',
    '🥂',
    '🍻',
    '🍺',
    '🍕',
    '🍔',
    '🍟',
    '🌭',
    '🍿',
    '🥓',
    '🍝',
    '🍣',
    '🍩',
    '🍪',
    '🍫',
    '🍦',
    '☕',
    '🥤',
    '🧃',
    '🍷',
    '🍹',
    '🎁',
    '🎈',
  ]),
  EmojiCategory('Animali e natura', Icons.pets_rounded, [
    '🐐',
    '🦁',
    '🐯',
    '🐺',
    '🦊',
    '🐻',
    '🐼',
    '🐶',
    '🐱',
    '🐭',
    '🐵',
    '🙈',
    '🙉',
    '🙊',
    '🦅',
    '🦉',
    '🐍',
    '🐉',
    '🦈',
    '🐝',
    '🐢',
    '🦄',
    '🐔',
    '🐷',
    '🐮',
    '🌍',
    '🌙',
    '☀️',
    '⛈️',
    '❄️',
    '🌈',
    '🌊',
    '⚡',
    '🍀',
    '🌹',
  ]),
  EmojiCategory('Oggetti', Icons.lightbulb_rounded, [
    '📱',
    '💻',
    '🖥️',
    '⌨️',
    '🖱️',
    '📷',
    '📹',
    '🎥',
    '📺',
    '🔊',
    '🔇',
    '🔔',
    '🔕',
    '📌',
    '📎',
    '✏️',
    '📝',
    '📅',
    '📊',
    '📈',
    '📉',
    '💡',
    '🔑',
    '🔒',
    '🔓',
    '💰',
    '💸',
    '🧨',
    '💣',
    '🚀',
    '✈️',
    '🚗',
    '🏠',
    '⏳',
    '🛠️',
    '⚙️',
    '🩹',
    '💊',
  ]),
  EmojiCategory('Bandiere', Icons.flag_rounded, [
    '🇮🇹',
    '🇪🇸',
    '🇫🇷',
    '🇩🇪',
    '🇵🇹',
    '🇳🇱',
    '🇧🇪',
    '🇭🇷',
    '🇬🇧',
    '🇨🇭',
    '🇦🇹',
    '🇵🇱',
    '🇷🇴',
    '🇦🇱',
    '🇷🇸',
    '🇬🇷',
    '🇹🇷',
    '🇧🇷',
    '🇦🇷',
    '🇺🇾',
    '🇺🇸',
    '🇲🇦',
    '🇸🇳',
    '🇳🇬',
    '🇯🇵',
    '🇰🇷',
    '🇪🇺',
    '🏳️',
    '🏴',
  ]),
];

/// I caratteri di cui sono fatte le emoji (simboli, selettori, giunzioni, bandiere): la
/// stessa regola di `valid_reaction` nel database.
final _emojiOnly = RegExp(
  r'^[\u{1F000}-\u{1FAFF}\u{2190}-\u{2BFF}\u{203C}\u{2049}\u{2122}\u{2139}'
  r'\u{3030}\u{303D}\u{3297}\u{3299}\u{A9}\u{AE}\u{FE0F}\u{200D}\u{20E3}'
  r'\u{E0020}-\u{E007F}]+$',
  unicode: true,
);
final _emojiBase = RegExp(
  r'[\u{1F000}-\u{1F3FA}\u{1F400}-\u{1FAFF}\u{2190}-\u{2BFF}\u{203C}\u{2049}'
  r'\u{2122}\u{2139}\u{3030}\u{303D}\u{3297}\u{3299}\u{A9}\u{AE}]',
  unicode: true,
);

/// [text] è una sola emoji che il server accetta come reazione.
bool isReactionEmoji(String text) =>
    text.isNotEmpty &&
    text.runes.length <= 12 &&
    _emojiOnly.hasMatch(text) &&
    _emojiBase.hasMatch(text);

/// Quante emoji ci sono in [text] se è fatto solo di emoji (da 1 a 3, spazi a parte);
/// 0 altrimenti. I messaggi così si scrivono più grandi, come nelle altre chat.
int emojiOnlyCount(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty || !_emojiOnly.hasMatch(compact)) return 0;
  final count = compact.characters.length;
  return count <= 3 && _emojiBase.hasMatch(compact) ? count : 0;
}

/// Le emoji usate di recente su questo telefono (le prime sono le ultime usate).
final recentEmojisProvider = NotifierProvider<RecentEmojis, List<String>>(
  RecentEmojis.new,
);

class RecentEmojis extends Notifier<List<String>> {
  static const _key = 'chat.emoji_recenti';
  static const _max = 24;

  @override
  List<String> build() {
    ref.read(localFlagsProvider).getList(_key).then((saved) {
      // Una scelta fatta nel frattempo resta davanti.
      if (!ref.mounted) return;
      state = [
        ...state,
        ...saved.where((e) => !state.contains(e)),
      ].take(_max).toList();
    }).ignore();
    return const [];
  }

  void used(String emoji) {
    state = [emoji, ...state.where((e) => e != emoji)].take(_max).toList();
    ref.read(localFlagsProvider).setList(_key, state).ignore();
  }
}

/// Il selettore di emoji: le usate di recente e i gruppi, a schede. [onPick] riceve
/// l'emoji toccata (il selettore resta aperto: se ne possono mettere più di una).
class EmojiPanel extends ConsumerStatefulWidget {
  const EmojiPanel({super.key, required this.onPick, this.height = 264});
  final ValueChanged<String> onPick;
  final double height;

  @override
  ConsumerState<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends ConsumerState<EmojiPanel> {
  /// -1 = usate di recente.
  int? _category;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final recent = ref.watch(recentEmojisProvider);
    // Si apre sulle recenti se ce ne sono, altrimenti sulle faccine.
    final category = _category ?? (recent.isEmpty ? 0 : -1);
    final showing = category == -1 && recent.isEmpty ? 0 : category;
    final emojis = showing == -1 ? recent : emojiCategories[showing].emojis;

    Widget tab(int index, IconData icon, String label) {
      final selected = index == showing;
      return Tooltip(
        message: label,
        child: InkResponse(
          onTap: () => setState(() => _category = index),
          radius: 22,
          child: Semantics(
            button: true,
            selected: selected,
            label: label,
            child: Container(
              width: 40,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? p.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected ? p.accentText : p.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                if (recent.isNotEmpty)
                  tab(-1, Icons.history_rounded, 'Usate di recente'),
                for (final (i, c) in emojiCategories.indexed)
                  tab(i, c.icon, c.label),
              ],
            ),
          ),
          Divider(height: 1, color: p.divider),
          Expanded(
            child: GridView.builder(
              key: ValueKey('emoji-$showing'),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 46,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, i) {
                final emoji = emojis[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    ref.read(recentEmojisProvider.notifier).used(emoji);
                    widget.onPick(emoji);
                  },
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Il selettore in un pannello dal basso: restituisce l'emoji scelta (null se si chiude).
Future<String?> showEmojiSheet(BuildContext context, {String? title}) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.pal.text,
                  ),
                ),
              ),
            EmojiPanel(height: 300, onPick: (e) => Navigator.pop(c, e)),
          ],
        ),
      ),
    );
