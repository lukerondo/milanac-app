import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/appearance.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/notify_prefs.dart';
import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/haptics.dart';
import '../../core/push/device_tokens.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/gold_loader.dart';
import '../../shared/member_photo.dart';
import '../../shared/ui.dart';
import '../auth/gate_ui.dart';
import '../carta/carta_page.dart';
import '../privacy/privacy_page.dart';
import '../registrazione/registration_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import '../volto/face.dart';
import '../volto/face_editor_page.dart';
import '../volto/face_view.dart';

/// Impostazioni (dal profilo, a schermo intero): profilo, notifiche, aspetto e account.
class ImpostazioniPage extends ConsumerStatefulWidget {
  const ImpostazioniPage({super.key, this.initialSection});

  /// Sezione da portare in vista all'apertura: "notifiche" (campanella della Home).
  final String? initialSection;

  @override
  ConsumerState<ImpostazioniPage> createState() => _ImpostazioniPageState();
}

class _ImpostazioniPageState extends ConsumerState<ImpostazioniPage> {
  final _notifiche = GlobalKey();
  final _aspetto = GlobalKey();

  /// Preferenze appena toccate, mostrate subito mentre si salvano.
  NotifyPrefs? _pendingPrefs;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final key = switch (widget.initialSection) {
      'notifiche' => _notifiche,
      'aspetto' => _aspetto,
      _ => null,
    };
    if (key != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = key.currentContext;
        if (target == null || !mounted) return;
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// La versione più recente del membro (il volto potrebbe essere appena cambiato).
  Member? _live(String id) =>
      ref.read(rosaProvider).value?.where((m) => m.id == id).firstOrNull;

  Future<void> _changeFace(Member member) async {
    final face = await Navigator.of(context, rootNavigator: true).push<Face>(
      MaterialPageRoute(
        builder: (_) => FaceEditorPage(initial: member.face ?? Face.defaults),
      ),
    );
    if (face == null || !mounted) return;
    final current = _live(member.id) ?? member;
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
      Haptics.light();
      if (mounted) _toast('Volto aggiornato: lo vedi anche sulla carta.');
    } catch (e) {
      if (mounted) _toast(friendlyError(e, action: 'Salvataggio non riuscito'));
    }
  }

  Future<void> _setNotify(
    NotifyPrefs current,
    NotifyCategory c,
    bool on,
  ) async {
    final next = current.set(c, on);
    setState(() => _pendingPrefs = next);
    try {
      await ref.read(notifyPrefsRepositoryProvider).save(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingPrefs = null);
      _toast(friendlyError(e, action: 'Preferenze non salvate'));
    }
  }

  Future<void> _changePassword() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _PasswordDialog(title: 'Cambia password'),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(authRepositoryProvider).updatePassword(result.$2);
      if (mounted) _toast('Password aggiornata.');
    } catch (e) {
      if (mounted) _toast(friendlyAuthError(e));
    }
  }

  Future<void> _changeDirettivoPassword() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _PasswordDialog(
        title: 'Password del Direttivo',
        askCurrent: true,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(registrationRepositoryProvider)
          .changeDirettivoPassword(result.$1, result.$2);
      if (mounted) _toast('Password del Direttivo aggiornata.');
    } catch (e) {
      if (mounted) _toast(friendlyRegistrationError(e));
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
              foregroundColor: Theme.of(c).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      // Dopo l'eliminazione la sessione si chiude e il router porta al login.
      await ref.read(authRepositoryProvider).deleteAccount();
    } catch (e) {
      if (mounted) {
        _toast(friendlyError(e, action: 'Eliminazione non riuscita'));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final me = ref.watch(profileProvider).value;
    final rosa = ref.watch(rosaProvider);
    final member = me == null
        ? null
        : rosa.value?.where((m) => m.id == me.id).firstOrNull;
    final prefs = _pendingPrefs ?? me?.notifyPrefs ?? const NotifyPrefs();
    final appearance = ref.watch(appearanceProvider);

    // Aperte come unica pagina (con un link): indietro porta al profilo, da cui si
    // arriva qui, invece di chiudere l'app.
    return PopScope(
      canPop: !(ModalRoute.of(context)?.isFirst ?? false),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/profilo');
      },
      child: Scaffold(
        appBar: gateAppBar(
          title: 'IMPOSTAZIONI',
          divider: true,
          leading: BackArrow(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/profilo'),
          ),
        ),
        body: ContentWidth(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _GroupLabel('Profilo', first: true),
                _Group(
                  children: [
                    if (member == null)
                      _ProfileLoading(
                        failed: rosa.hasError,
                        onRetry: () => ref.invalidate(rosaProvider),
                      )
                    else ...[
                      _Row(
                        title: 'Dati personali',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _PersonalDataPage(member: member),
                          ),
                        ),
                      ),
                      _Row(
                        title: 'Il tuo volto',
                        trailing: _FaceThumb(member.face ?? Face.defaults),
                        onTap: () => _changeFace(member),
                      ),
                      _Row(
                        title: 'La tua carta',
                        detail: cardSummary(member),
                        onTap: () => showCardEditor(context, member),
                      ),
                    ],
                  ],
                ),
                _GroupLabel('Notifiche', key: _notifiche),
                _Group(
                  children: [
                    for (final c in NotifyCategory.values)
                      SwitchListTile(
                        value: prefs.isOn(c),
                        onChanged: me == null
                            ? null
                            : (on) => _setNotify(prefs, c, on),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        title: Text(
                          c.label,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Formazione, risultati, carte speciali, regolamento e avvisi '
                    'del Direttivo arrivano sempre.',
                    style: TextStyle(color: p.textMuted, fontSize: 14),
                  ),
                ),
                _GroupLabel('Aspetto', key: _aspetto),
                SegmentedTabs(
                  labels: [for (final a in Appearance.values) a.label],
                  selected: appearance.index,
                  onSelected: (i) => ref
                      .read(appearanceProvider.notifier)
                      .set(Appearance.values[i]),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Automatico segue il tema chiaro o scuro del telefono.',
                    style: TextStyle(color: p.textMuted, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 8),
                _Group(
                  children: [
                    SwitchListTile(
                      title: const Text('Vibrazioni'),
                      subtitle: const Text(
                        'Ai tocchi, ai gol, alle presenze e alle conferme.',
                      ),
                      value: ref.watch(vibrationsProvider),
                      onChanged: (on) =>
                          ref.read(vibrationsProvider.notifier).set(on),
                    ),
                  ],
                ),
                const _GroupLabel('Account'),
                _Group(
                  children: [
                    _Row(title: 'Cambia password', onTap: _changePassword),
                    if (me?.isDirettivo ?? false)
                      _Row(
                        title: 'Password del Direttivo',
                        onTap: _changeDirettivoPassword,
                      ),
                    _Row(
                      title: 'Privacy',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PrivacyPage(),
                        ),
                      ),
                    ),
                  ],
                ),
                // In demo non c'è un account da cui uscire.
                if (!AppConfig.isDemo) ...[
                  const SizedBox(height: 16),
                  const LogoutTile(),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: _deleting ? null : _deleteAccount,
                      style: TextButton.styleFrom(foregroundColor: p.danger),
                      child: _deleting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: GoldLoader(size: 18),
                            )
                          : const Text('Elimina il mio account'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Riassunto della carta: "CC · n. 10 · PS5".
String cardSummary(Member m) => [
  ?m.fieldPosition,
  if (m.shirtNumber != null) 'n. ${m.shirtNumber}',
  if (m.platform != null)
    switch (m.platform!) {
      GamePlatform.ps5 => 'PS5',
      GamePlatform.xbox => 'Xbox',
      GamePlatform.pc => 'PC',
    },
].join(' · ');

/// Etichetta di un gruppo (PROFILO, NOTIFICHE, ...).
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {super.key, this.first = false});
  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(4, first ? 4 : 18, 4, 10),
    child: SectionLabel(text),
  );
}

/// Card con le voci di un gruppo, separate da un filo sottile.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    radius: 16,
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) Divider(height: 1, indent: 16, color: context.pal.divider),
          c,
        ],
      ],
    ),
  );
}

/// Voce di un gruppo: titolo, dettaglio a destra e freccetta.
class _Row extends StatelessWidget {
  const _Row({required this.title, this.onTap, this.detail, this.trailing});
  final String title;
  final VoidCallback? onTap;
  final String? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 16, color: p.text),
                ),
              ),
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  detail!,
                  style: TextStyle(fontSize: 14, color: p.textMuted),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: p.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il volto in piccolo, nel cerchio con il bordo oro.
class _FaceThumb extends StatelessWidget {
  const _FaceThumb(this.face);
  final Face face;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    padding: const EdgeInsets.all(1.5),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.pal.chipBorder,
    ),
    child: ClipOval(
      child: FaceView(
        face: face,
        size: 27,
        crop: FaceCrop.head,
        // Fondo scuro fisso, come le foto dei membri nel resto dell'app.
        background: MilanacColors.surfaceHigh,
      ),
    ),
  );
}

/// Il profilo non è ancora arrivato (o non si carica): attesa o Riprova.
class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading({required this.failed, required this.onRetry});
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Center(
      child: failed
          ? TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Impossibile caricare il profilo. Riprova'),
            )
          : const SizedBox(width: 22, height: 22, child: GoldLoader(size: 22)),
    ),
  );
}

/// Dati personali: nome sulla carta, motto e i dati che vede solo il Direttivo.
class _PersonalDataPage extends ConsumerStatefulWidget {
  const _PersonalDataPage({required this.member});
  final Member member;

  @override
  ConsumerState<_PersonalDataPage> createState() => _PersonalDataPageState();
}

class _PersonalDataPageState extends ConsumerState<_PersonalDataPage> {
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
    // La versione più recente del membro (il volto potrebbe essere appena cambiato).
    final current =
        ref
            .read(rosaProvider)
            .value
            ?.where((m) => m.id == widget.member.id)
            .firstOrNull ??
        widget.member;
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
      if (!mounted) return;
      _toast('Dati salvati.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _toast(friendlyError(e, action: 'Salvataggio non riuscito'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: gateAppBar(title: 'DATI PERSONALI', divider: true),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            LabeledField(
              label: 'Nome sulla maglia e sulla carta',
              child: TextField(
                controller: _cardName,
                maxLength: 14,
                textCapitalization: TextCapitalization.characters,
              ),
            ),
            const SizedBox(height: 6),
            LabeledField(
              label: 'Il tuo motto',
              child: TextField(
                controller: _motto,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            const SizedBox(height: 10),
            const SectionLabel('Anagrafica'),
            const SizedBox(height: 4),
            Text(
              'Nome, cognome e anno di nascita li vede solo il Direttivo.',
              style: TextStyle(color: p.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Nome',
                    child: TextField(
                      controller: _firstName,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LabeledField(
                    label: 'Cognome',
                    child: TextField(
                      controller: _lastName,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Anno di nascita',
                    child: TextField(
                      controller: _birthYear,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: LabeledField(
                    label: 'Gamertag / ID EA',
                    child: TextField(controller: _gamertag),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Città',
              child: TextField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Nazionalità',
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: nationalities.containsKey(_nationality)
                    ? _nationality
                    : null,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Non indicata'),
                  ),
                  for (final MapEntry(:key, :value) in nationalities.entries)
                    DropdownMenuItem(
                      value: key,
                      child: Text('${flagEmoji(key)}  $value'),
                    ),
                ],
                onChanged: (v) => setState(() => _nationality = v),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Piede preferito',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: p.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in PreferredFoot.values)
                  ChoicePill(
                    label: f.label,
                    selected: _foot == f,
                    onTap: () => setState(() => _foot = _foot == f ? null : f),
                  ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        child: PrimaryButton(
          label: 'Salva i dati',
          fontSize: 16,
          busy: _saving,
          onPressed: _save,
        ),
      ),
    );
  }
}

/// "Esci dall'account": prima l'uscita (token delle notifiche, poi la sessione), con
/// l'attesa sul pulsante; quando la sessione si chiude è il router a portare al login.
/// La pagina non si chiude prima, così `ref` non si usa mai dopo che è sparita.
class LogoutTile extends ConsumerStatefulWidget {
  const LogoutTile({super.key});

  @override
  ConsumerState<LogoutTile> createState() => _LogoutTileState();
}

class _LogoutTileState extends ConsumerState<LogoutTile> {
  bool _busy = false;

  Future<void> _logout() async {
    setState(() => _busy = true);
    try {
      await logout(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, action: 'Uscita non riuscita')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final radius = BorderRadius.circular(16);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: p.border),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: _busy ? null : _logout,
        child: SizedBox(
          height: 52,
          child: Center(
            child: _busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: GoldLoader(size: 20, color: p.danger),
                  )
                : Text(
                    'Esci dall\'account',
                    style: TextStyle(
                      color: p.danger,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Nuova password (con quella attuale per la password del Direttivo): restituisce
/// (attuale, nuova).
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title, this.askCurrent = false});
  final String title;
  final bool askCurrent;

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
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.askCurrent) ...[
            TextField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password attuale'),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Nuova password (almeno 8 caratteri)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Ripeti la nuova password',
            ),
          ),
        ],
      ),
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
