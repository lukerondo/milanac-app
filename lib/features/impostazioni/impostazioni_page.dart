import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/push/device_tokens.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../carta/carta_page.dart';
import '../privacy/privacy_page.dart';
import '../registrazione/registration_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import '../volto/face.dart';
import '../volto/face_editor_page.dart';
import '../volto/face_view.dart';

/// Pulsante ingranaggio nella barra in alto.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Impostazioni',
    icon: const Icon(Icons.settings_rounded),
    onPressed: () => context.push('/impostazioni'),
  );
}

/// Impostazioni: volto, nome sulla carta, dati personali e account.
class ImpostazioniPage extends ConsumerWidget {
  const ImpostazioniPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final rosa = ref.watch(rosaProvider);
    final member = me == null
        ? null
        : rosa.value?.where((m) => m.id == me.id).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('IMPOSTAZIONI')),
      body: member == null
          ? Center(
              child: rosa.hasError
                  ? TextButton(
                      onPressed: () => ref.invalidate(rosaProvider),
                      child: const Text(
                        'Impossibile caricare il profilo. Riprova',
                      ),
                    )
                  : const CircularProgressIndicator(),
            )
          : _ProfileForm(key: ValueKey(member.id), member: member),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({super.key, required this.member});
  final Member member;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final _cardName = TextEditingController(text: widget.member.displayName);
  late final _motto = TextEditingController(text: widget.member.motto);
  late final _firstName = TextEditingController(text: widget.member.firstName);
  late final _lastName = TextEditingController(text: widget.member.lastName);
  late final _birthYear = TextEditingController(
    text: widget.member.birthYear?.toString(),
  );
  late final _gamertag = TextEditingController(text: widget.member.gamertag);
  late final _city = TextEditingController(text: widget.member.city);
  late String? _nationality = widget.member.nationality;
  late PreferredFoot? _foot = widget.member.preferredFoot;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _cardName,
      _motto,
      _firstName,
      _lastName,
      _birthYear,
      _gamertag,
      _city,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// La versione più recente del membro (il volto potrebbe essere appena cambiato).
  Member get _live =>
      ref
          .read(rosaProvider)
          .value
          ?.where((m) => m.id == widget.member.id)
          .firstOrNull ??
      widget.member;

  Future<void> _changeFace() async {
    final current = _live;
    final face = await Navigator.of(context, rootNavigator: true).push<Face>(
      MaterialPageRoute(
        builder: (_) => FaceEditorPage(initial: current.face ?? Face.defaults),
      ),
    );
    if (face == null || !mounted) return;
    try {
      await ref
          .read(rosaRepositoryProvider)
          .saveProfile(
            current.withPersonalData(
              displayName: current.displayName,
              gamertag: current.gamertag,
              birthDate: current.birthDate,
              city: current.city,
              nationality: current.nationality,
              preferredFoot: current.preferredFoot,
              face: face,
            ),
          );
      HapticFeedback.lightImpact();
      _toast('Volto aggiornato: lo vedi anche sulla carta.');
    } catch (e) {
      _toast('Salvataggio non riuscito: $e');
    }
  }

  Future<void> _save() async {
    final card = _text(_cardName);
    if (card == null || card.length < 2) {
      _toast('Scegli il nome da mettere sulla carta.');
      return;
    }
    if (card.length > 14) {
      _toast('Il nome sulla carta può avere al massimo 14 caratteri.');
      return;
    }
    final yearText = _text(_birthYear);
    final year = yearText == null ? null : int.tryParse(yearText);
    if (yearText != null &&
        (year == null || year < 1940 || year > DateTime.now().year - 8)) {
      _toast('Anno di nascita non valido.');
      return;
    }
    setState(() => _saving = true);
    final current = _live;
    try {
      await ref
          .read(rosaRepositoryProvider)
          .saveProfile(
            current.withPersonalData(
              displayName: card,
              gamertag: _text(_gamertag),
              birthDate: current.birthDate,
              city: _text(_city),
              nationality: _nationality,
              preferredFoot: _foot,
              firstName: _text(_firstName) ?? current.firstName,
              lastName: _text(_lastName) ?? current.lastName,
              birthYear: year ?? current.birthYear,
              motto: _text(_motto),
            ),
          );
      _toast('Dati salvati.');
    } catch (e) {
      _toast('Salvataggio non riuscito: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeDirettivoPassword() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(registrationRepositoryProvider)
          .changeDirettivoPassword(result.$1, result.$2);
      _toast('Password del Direttivo aggiornata.');
    } catch (e) {
      _toast(friendlyRegistrationError(e));
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminare il tuo account?'),
        content: const Text(
          'Verranno cancellati definitivamente il tuo account, il profilo e lo storico '
          'delle presenze. Per rientrare dovrai registrarti di nuovo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('Eliminazione non riuscita: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final live =
        ref
            .watch(rosaProvider)
            .value
            ?.where((m) => m.id == widget.member.id)
            .firstOrNull ??
        widget.member;
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A0A0E), MilanacColors.surface],
              ),
              border: Border.all(
                color: MilanacColors.gold.withValues(alpha: .5),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: FaceView(face: live.face ?? Face.defaults, size: 132),
            ),
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: _changeFace,
            icon: const Icon(Icons.face_retouching_natural_rounded),
            label: const Text('Cambia il volto'),
          ),
        ),
        const Text(
          'Il volto compare in Rosa, in chat e sulla tua carta.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const _SectionTitle('IL TUO NOME'),
        TextField(
          controller: _cardName,
          maxLength: 14,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Nome sulla maglia e sulla carta',
          ),
        ),
        TextField(
          controller: _motto,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Il tuo motto'),
        ),
        const _SectionTitle('DATI PERSONALI'),
        const Text(
          'Nome, cognome e anno di nascita li vede solo il Direttivo.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _firstName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _lastName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Cognome'),
              ),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                controller: _birthYear,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(labelText: 'Anno di nascita'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _gamertag,
                decoration: const InputDecoration(
                  labelText: 'Gamertag / ID EA',
                ),
              ),
            ),
          ],
        ),
        TextField(
          controller: _city,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Città'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: nationalities.containsKey(_nationality)
              ? _nationality
              : null,
          decoration: const InputDecoration(labelText: 'Nazionalità'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Non indicata')),
            for (final MapEntry(:key, :value) in nationalities.entries)
              DropdownMenuItem(
                value: key,
                child: Text('${flagEmoji(key)}  $value'),
              ),
          ],
          onChanged: (v) => setState(() => _nationality = v),
        ),
        const SizedBox(height: 12),
        const Text('Piede preferito'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final f in PreferredFoot.values)
              ChoiceChip(
                label: Text(f.label),
                selected: _foot == f,
                onSelected: (on) => setState(() => _foot = on ? f : null),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Salva i dati'),
          ),
        ),
        const _SectionTitle('CARTA E APP'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.style_rounded, color: MilanacColors.gold),
          title: const Text('La mia carta'),
          subtitle: const Text('Ruolo, numero, stile di gioco, piattaforma'),
          onTap: () => showCardEditor(context, live),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.library_music_rounded),
          title: const Text('Colonna sonora'),
          onTap: () {
            Navigator.of(context).pop();
            context.go('/musica');
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy'),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const PrivacyPage())),
        ),
        const _SectionTitle('ACCOUNT'),
        if (isDirettivo)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key_rounded, color: MilanacColors.gold),
            title: const Text('Password del Direttivo'),
            subtitle: const Text('Quella che serve per entrare nel Direttivo'),
            onTap: _changeDirettivoPassword,
          ),
        if (!AppConfig.isDemo) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Esci'),
            onTap: () {
              Navigator.of(context).pop();
              logout(ref);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.person_off_outlined,
              color: Colors.redAccent,
            ),
            title: const Text(
              'Elimina il mio account',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: _deleteAccount,
          ),
        ],
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _ok() {
    if (_next.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La nuova password deve avere almeno 8 caratteri.'),
        ),
      );
      return;
    }
    if (_next.text != _confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le due password non coincidono.')),
      );
      return;
    }
    Navigator.pop(context, (_current.text, _next.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Password del Direttivo'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _current,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password attuale'),
        ),
        TextField(
          controller: _next,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Nuova password'),
        ),
        TextField(
          controller: _confirm,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Ripeti la nuova password',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(onPressed: _ok, child: const Text('Cambia')),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 24, 0, 4),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: sportFont,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
        color: MilanacColors.gold,
      ),
    ),
  );
}
