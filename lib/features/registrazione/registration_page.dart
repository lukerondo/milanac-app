import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/push/device_tokens.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/ui.dart';
import '../auth/gate_ui.dart';
import '../rosa/member.dart';
import '../volto/face.dart';
import '../volto/face_editor.dart';
import '../volto/face_view.dart';
import 'registration_repository.dart';

/// Registrazione in tre passi: chi sei, squadra e ruolo, il tuo volto.
/// Alla fine il profilo è completo; manca solo l'accettazione del regolamento.
class RegistrationPage extends ConsumerStatefulWidget {
  const RegistrationPage({super.key, this.initialStep = 1});

  /// Passo di partenza (1-3): solo in demo, per provare le schermate.
  final int initialStep;

  @override
  ConsumerState<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends ConsumerState<RegistrationPage> {
  late final _pages = PageController(initialPage: _step);
  late int _step = AppConfig.isDemo ? (widget.initialStep - 1).clamp(0, 2) : 0;
  bool _saving = false;
  bool _prefilled = false;

  // Passo 1.
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _cardName = TextEditingController();
  final _motto = TextEditingController();
  final _birthYear = TextEditingController();

  // Passo 2.
  Set<Team> _teams = {Team.milanac};
  bool _direttivo = false;
  final _password = TextEditingController();
  bool _hidden = true;

  /// Password rifiutata dal server (sbagliata o troppi tentativi): evidenziata sul campo.
  String? _passwordError;
  final _roles = <DirettivoRole>{};
  String? _position;
  final _number = TextEditingController();
  GamePlatform? _platform;

  // Passo 3.
  Face _face = Face.random();

  @override
  void dispose() {
    _pages.dispose();
    for (final c in [
      _firstName,
      _lastName,
      _cardName,
      _motto,
      _birthYear,
      _password,
      _number,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Nome e cognome dall'account social (es. "Mario Rossi"), se non già inseriti.
  void _prefill(Profile p) {
    if (_prefilled) return;
    _prefilled = true;
    final words = p.displayName.trim().split(RegExp(r'\s+'));
    _firstName.text = p.firstName ?? (words.length > 1 ? words.first : '');
    _lastName.text =
        p.lastName ?? (words.length > 1 ? words.sublist(1).join(' ') : '');
    _cardName.text = p.lastName != null ? p.displayName : '';
    _motto.text = p.motto ?? '';
    if (p.birthYear != null) _birthYear.text = '${p.birthYear}';
    _position = p.fieldPosition;
    _platform = GamePlatform.values.asNameMap()[p.platform];
    if (p.shirtNumber != null) _number.text = '${p.shirtNumber}';
    if (p.face != null) _face = p.face!;
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_firstName.text.trim().isEmpty) return 'Scrivi il tuo nome.';
        if (_lastName.text.trim().isEmpty) return 'Scrivi il tuo cognome.';
        final year = int.tryParse(_birthYear.text.trim());
        if (year == null) return 'Scrivi il tuo anno di nascita.';
        if (year < 1940 || year > DateTime.now().year - 8) {
          return 'Anno di nascita non valido.';
        }
        final card = _cardName.text.trim();
        if (card.length < 2) return 'Scegli il nome da mettere sulla carta.';
        if (card.length > 14) {
          return 'Il nome sulla carta può avere al massimo 14 caratteri.';
        }
        if (_motto.text.length > 80) return 'Il motto è troppo lungo.';
      case 1:
        if (_teams.isEmpty) return 'Scegli la tua squadra.';
        if (_direttivo) {
          if (_password.text.isEmpty) {
            return 'Inserisci la password del Direttivo.';
          }
          if (_roles.isEmpty) return 'Scegli almeno un ruolo nel Direttivo.';
        }
        if (_position == null) return 'Scegli il tuo ruolo in campo.';
        final n = _number.text.trim();
        if (n.isNotEmpty) {
          final v = int.tryParse(n);
          if (v == null || v < 1 || v > 99) {
            return 'Il numero di maglia va da 1 a 99.';
          }
        }
    }
    return null;
  }

  void _next() {
    final error = _validateStep(_step);
    if (error != null) {
      _toast(error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step++);
    _pages.animateToPage(
      _step,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
    _pages.animateToPage(
      _step,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  RegistrationData get _data => RegistrationData(
    firstName: _firstName.text.trim(),
    lastName: _lastName.text.trim(),
    birthYear: int.parse(_birthYear.text.trim()),
    cardName: _cardName.text.trim(),
    motto: _motto.text.trim().isEmpty ? null : _motto.text.trim(),
    teams: _direttivo ? _teams : {_teams.first},
    direttivo: _direttivo,
    direttivoPassword: _password.text,
    direttivoRoles: _roles.toList(),
    fieldPosition: _position!,
    shirtNumber: int.tryParse(_number.text.trim()),
    platform: _platform,
    face: _face,
  );

  Future<void> _complete() async {
    for (final s in [0, 1]) {
      final error = _validateStep(s);
      if (error != null) {
        _toast(error);
        setState(() => _step = s);
        _pages.jumpToPage(s);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await ref.read(registrationRepositoryProvider).complete(_data);
    } catch (e) {
      if (!mounted) return;
      if (isDirettivoPasswordError(e)) {
        // Si torna al passo 2, sul campo della password.
        setState(() {
          _step = 1;
          _passwordError = friendlyRegistrationError(e);
        });
        _pages.jumpToPage(1);
      }
      _toast(friendlyRegistrationError(e));
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    // Il router porta al regolamento appena il profilo riletto risulta completo, senza
    // aspettare il tempo reale; in demo andiamo noi.
    ref.invalidate(profileProvider);
    if (AppConfig.isDemo) context.go('/regolamento/accetta');
  }

  void _retryProfile() => ref.invalidate(profileProvider);

  /// Profilo non ancora caricato: spinner, oppure l'errore con Riprova (anche mentre si
  /// riprova da soli) invece di uno spinner senza fine.
  Widget _profileState(AsyncValue<Profile?> state) {
    if (state.hasError) {
      return ErrorRetry(
        message: friendlyError(
          state.error!,
          action: 'Caricamento del profilo non riuscito',
        ),
        onRetry: _retryProfile,
      );
    }
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ErrorRetry(
      message: 'Profilo non trovato: riprova, oppure esci e rientra.',
      onRetry: _retryProfile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final profile = profileState.value;
    if (profile != null) _prefill(profile);
    final waiting =
        profile == null && (!AppConfig.isDemo || profileState.hasError);

    // Indietro di Android: al passo precedente (dal primo esce come sempre).
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: gateAppBar(
          title: 'REGISTRAZIONE',
          automaticallyImplyLeading: false,
          leading: _step > 0
              ? BackArrow(onPressed: _back)
              : AppConfig.isDemo
              ? null
              // Dal primo passo si torna all'accesso (uscendo dall'account).
              : BackArrow(
                  tooltip: 'Torna all\'accesso',
                  onPressed: () => logout(ref),
                ),
          actions: [
            if (!waiting)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    'Passo ${_step + 1} di 3',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.dark.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: waiting
            ? _profileState(profileState)
            : Column(
                children: [
                  _StepHeader(step: _step),
                  Expanded(
                    child: PageView(
                      controller: _pages,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [_stepWho(), _stepTeam(), _stepFace()],
                    ),
                  ),
                  BottomActionBar(
                    child: Row(
                      children: [
                        if (_step > 0) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving ? null : _back,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                              ),
                              child: const Text('Indietro'),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          flex: 2,
                          child: PrimaryButton(
                            label: _step < 2
                                ? 'Avanti'
                                : 'Completa la registrazione',
                            fontSize: 16,
                            busy: _saving,
                            onPressed: _step < 2 ? _next : _complete,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _frame(int step, List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: ListView(
        key: ValueKey('step-$step'),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: children,
      ),
    ),
  );

  Widget _stepWho() {
    return _frame(1, [
      const _Legend(
        'Chi sei?',
        text:
            'Nome e cognome li vede solo il Direttivo. Nella rosa, in chat e '
            'sulla carta compare il nome che scegli qui sotto.',
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LabeledField(
              label: 'Nome',
              child: TextField(
                controller: _firstName,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.givenName],
                textInputAction: TextInputAction.next,
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
                autofillHints: const [AutofillHints.familyName],
                textInputAction: TextInputAction.next,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      LabeledField(
        label: 'Anno di nascita',
        child: TextField(
          controller: _birthYear,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(hintText: 'Es. 1998'),
        ),
      ),
      const SizedBox(height: 14),
      LabeledField(
        label: 'Nome sulla maglia e sulla carta',
        child: TextField(
          controller: _cardName,
          maxLength: 14,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Es. ROSSI, IL DIAVOLO, MARIO10',
          ),
        ),
      ),
      _CardNamePreview(name: _cardName.text, face: _face),
      const SizedBox(height: 14),
      LabeledField(
        label: 'Il tuo motto (facoltativo)',
        help: 'Compare sotto la tua carta.',
        child: TextField(
          controller: _motto,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
        ),
      ),
    ]);
  }

  Widget _stepTeam() => _frame(2, [
    _Legend(
      'In quale squadra giochi?',
      text: _direttivo ? 'Chi è del Direttivo può stare in entrambe.' : null,
    ),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, t) in Team.values.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _TeamCard(
              team: t,
              selected: _teams.contains(t),
              onTap: () => setState(() {
                if (!_direttivo) {
                  _teams = {t};
                  return;
                }
                final next = {..._teams};
                next.contains(t) ? next.remove(t) : next.add(t);
                if (next.isNotEmpty) _teams = next;
              }),
            ),
          ),
        ],
      ],
    ),
    const SizedBox(height: 18),
    const _SmallLabel('Entri come'),
    const SizedBox(height: 8),
    SegmentedTabs(
      labels: const ['Giocatore', 'Direttivo'],
      selected: _direttivo ? 1 : 0,
      onSelected: (i) => setState(() {
        _direttivo = i == 1;
        if (!_direttivo) _teams = {_teams.first};
      }),
    ),
    const SizedBox(height: 8),
    const _Help('Per il Direttivo serve la password del club.'),
    if (_direttivo) ...[
      const SizedBox(height: 14),
      LabeledField(
        label: 'Password del Direttivo',
        child: TextField(
          controller: _password,
          obscureText: _hidden,
          onChanged: (_) {
            if (_passwordError != null) setState(() => _passwordError = null);
          },
          decoration: InputDecoration(
            errorText: _passwordError,
            errorMaxLines: 3,
            suffixIcon: ShowPasswordButton(
              hidden: _hidden,
              onPressed: () => setState(() => _hidden = !_hidden),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      const _SmallLabel('Ruoli nel Direttivo'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in DirettivoRole.values)
            ChoicePill(
              label: r.label,
              selected: _roles.contains(r),
              onTap: () => setState(
                () => _roles.contains(r) ? _roles.remove(r) : _roles.add(r),
              ),
            ),
        ],
      ),
    ],
    const SizedBox(height: 18),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: LabeledField(
            label: 'Ruolo in campo',
            child: DropdownButtonFormField<String>(
              initialValue: _position,
              isExpanded: true,
              hint: const Text('Scegli'),
              items: [
                for (final p in fieldPositions)
                  DropdownMenuItem(
                    value: p,
                    child: Text(
                      positionLabel(p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _position = v),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LabeledField(
            label: 'Numero',
            child: TextField(
              controller: _number,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 18),
    const _SmallLabel('Piattaforma'),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in GamePlatform.values)
          ChoicePill(
            label: p.label,
            selected: _platform == p,
            onTap: () => setState(() => _platform = _platform == p ? null : p),
          ),
      ],
    ),
    const SizedBox(height: 8),
    const _Help(
      'Con la piattaforma ricevi gli avvisi sugli aggiornamenti di console e gioco.',
    ),
  ]);

  Widget _stepFace() => _frame(3, [
    const _Legend(
      'Il tuo volto',
      text:
          'Compare sulla carta, nella rosa e in chat. Puoi cambiarlo quando vuoi '
          'dalle Impostazioni.',
    ),
    FaceEditor(face: _face, onChanged: (f) => setState(() => _face = f)),
  ]);
}

/// Ruolo in campo per esteso, come nel menu ("ATT · Attaccante").
String positionLabel(String position) {
  final name = _positionNames[position];
  return name == null ? position : '$position · $name';
}

const _positionNames = {
  'POR': 'Portiere',
  'DC': 'Difensore centrale',
  'TD': 'Terzino destro',
  'TS': 'Terzino sinistro',
  'CDC': 'Centrocampista difensivo',
  'CC': 'Centrocampista centrale',
  'COC': 'Centrocampista offensivo',
  'ED': 'Esterno destro',
  'ES': 'Esterno sinistro',
  'AD': 'Ala destra',
  'AS': 'Ala sinistra',
  'ATT': 'Attaccante',
};

/// I tre passi sotto la barra in alto: fatti, attuale, da fare.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});
  final int step;

  static const _titles = ['Dati', 'Squadra e ruolo', 'Volto'];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SubHeader(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < step
                          ? p.chipBorder
                          : i == step
                          ? p.accentText
                          : p.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _titles[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == step ? FontWeight.w700 : FontWeight.w400,
                      color: i < step
                          ? p.textSecondary
                          : i == step
                          ? p.text
                          : p.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Titolo del passo (Oswald) con una riga di spiegazione.
class _Legend extends StatelessWidget {
  const _Legend(this.title, {this.text});
  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GateTitle(title),
        if (text != null) ...[
          const SizedBox(height: 4),
          Text(
            text!,
            style: TextStyle(
              color: context.pal.textMuted,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ],
      ],
    ),
  );
}

class _SmallLabel extends StatelessWidget {
  const _SmallLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: context.pal.textSecondary,
    ),
  );
}

class _Help extends StatelessWidget {
  const _Help(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 13, color: context.pal.textMuted));
}

/// Scheda di una squadra: scelta con il bordo e la spunta in oro.
class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.selected,
    required this.onTap,
  });
  final Team team;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final radius = BorderRadius.circular(14);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? (p.isDark ? p.hero : p.accentTint) : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? p.accent : p.borderStrong,
            width: selected ? 2 : 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team.label,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: p.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        team == Team.milanac
                            ? 'Prima squadra'
                            : 'Seconda squadra',
                        style: TextStyle(fontSize: 14, color: p.textMuted),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: p.onAccent,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Anteprima del nome come apparirà sulla carta.
class _CardNamePreview extends StatelessWidget {
  const _CardNamePreview({required this.name, required this.face});
  final String name;
  final Face face;

  @override
  Widget build(BuildContext context) {
    final text = name.trim().isEmpty
        ? 'IL TUO NOME'
        : name.trim().toUpperCase();
    return AppCard(
      hero: true,
      radius: 14,
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      child: Row(
        children: [
          ClipOval(
            child: FaceView(
              face: face,
              size: 40,
              crop: FaceCrop.head,
              background: MilanacColors.surfaceHigh,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: sportFont,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: HeroText.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
