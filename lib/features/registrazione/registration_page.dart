import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/push/device_tokens.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
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
      HapticFeedback.mediumImpact();
      // Con Supabase il profilo si aggiorna da solo e il router porta al regolamento;
      // in demo andiamo noi.
      if (AppConfig.isDemo && mounted) context.go('/regolamento/accetta');
    } catch (e) {
      if (mounted) _toast(friendlyRegistrationError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    if (profile != null) _prefill(profile);

    return StadiumBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('REGISTRAZIONE'),
          leading: _step > 0
              ? IconButton(
                  tooltip: 'Indietro',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _back,
                )
              : null,
          actions: [
            if (!AppConfig.isDemo)
              IconButton(
                tooltip: 'Esci',
                icon: const Icon(Icons.logout_rounded),
                onPressed: () => logout(ref),
              ),
          ],
        ),
        body: profile == null && !AppConfig.isDemo
            ? const Center(child: CircularProgressIndicator())
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
                  _BottomBar(
                    step: _step,
                    saving: _saving,
                    onNext: _next,
                    onComplete: _complete,
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: children,
      ),
    ),
  );

  Widget _stepWho() {
    return _frame(1, [
      const _Intro(
        title: 'Chi sei',
        text:
            'Nome e cognome li vede solo il Direttivo. Nella rosa, in chat e '
            'sulla carta compare il nome che scegli qui sotto.',
      ),
      TextField(
        controller: _firstName,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.givenName],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Nome'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _lastName,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.familyName],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Cognome'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _birthYear,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Anno di nascita',
          hintText: 'Es. 1998',
        ),
      ),
      const SizedBox(height: 18),
      TextField(
        controller: _cardName,
        maxLength: 14,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Nome sulla maglia e sulla carta',
          helperText: 'Es. ROSSI, IL DIAVOLO, MARIO10',
        ),
      ),
      _CardNamePreview(name: _cardName.text, face: _face),
      const SizedBox(height: 10),
      TextField(
        controller: _motto,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Il tuo motto (facoltativo)',
          helperText: 'Compare sotto la tua carta',
        ),
      ),
    ]);
  }

  Widget _stepTeam() => _frame(2, [
    const _Intro(
      title: 'Squadra e ruolo',
      text:
          'I giocatori stanno in una squadra; chi è del Direttivo può stare '
          'in entrambe.',
    ),
    const _Label('SQUADRA'),
    Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final t in Team.values)
          if (_direttivo)
            FilterChip(
              label: Text(t.label),
              selected: _teams.contains(t),
              onSelected: (on) => setState(() {
                final next = {..._teams};
                on ? next.add(t) : next.remove(t);
                if (next.isNotEmpty) _teams = next;
              }),
            )
          else
            ChoiceChip(
              label: Text(t.label),
              selected: _teams.contains(t),
              onSelected: (_) => setState(() => _teams = {t}),
            ),
      ],
    ),
    const SizedBox(height: 12),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _direttivo,
      onChanged: (v) => setState(() {
        _direttivo = v;
        if (!v) _teams = {_teams.first};
      }),
      title: const Text('Faccio parte del Direttivo'),
      subtitle: const Text('Serve la password del club'),
    ),
    if (_direttivo) ...[
      TextField(
        controller: _password,
        obscureText: _hidden,
        decoration: InputDecoration(
          labelText: 'Password del Direttivo',
          prefixIcon: const Icon(Icons.key_rounded),
          suffixIcon: IconButton(
            tooltip: _hidden ? 'Mostra' : 'Nascondi',
            icon: Icon(
              _hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            ),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
      ),
      const SizedBox(height: 10),
      const _Label('RUOLI NEL DIRETTIVO'),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final r in DirettivoRole.values)
            FilterChip(
              label: Text(r.label),
              selected: _roles.contains(r),
              onSelected: (on) =>
                  setState(() => on ? _roles.add(r) : _roles.remove(r)),
            ),
        ],
      ),
    ],
    const SizedBox(height: 16),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _position,
            decoration: const InputDecoration(labelText: 'Ruolo in campo'),
            items: [
              for (final p in fieldPositions)
                DropdownMenuItem(value: p, child: Text(p)),
            ],
            onChanged: (v) => setState(() => _position = v),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Numero'),
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    const _Label('PIATTAFORMA'),
    Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final p in GamePlatform.values)
          ChoiceChip(
            label: Text(p.label),
            selected: _platform == p,
            onSelected: (on) => setState(() => _platform = on ? p : null),
          ),
      ],
    ),
    const SizedBox(height: 6),
    const Text(
      'Con la piattaforma ricevi gli avvisi sugli aggiornamenti di console e gioco.',
      style: TextStyle(color: Colors.white60, fontSize: 12),
    ),
  ]);

  Widget _stepFace() => _frame(3, [
    const _Intro(
      title: 'Il tuo volto',
      text:
          'Compare sulla carta, nella rosa e in chat. Puoi cambiarlo quando '
          'vuoi dalle Impostazioni.',
    ),
    FaceEditor(face: _face, onChanged: (f) => setState(() => _face = f)),
  ]);
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});
  final int step;

  static const _titles = ['Chi sei', 'Squadra e ruolo', 'Il tuo volto'];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
    child: Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              Expanded(
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: i <= step ? MilanacColors.red : Colors.white12,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (i < 2) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'PASSO ${step + 1} DI 3 · ${_titles[step].toUpperCase()}',
          style: const TextStyle(
            fontFamily: sportFont,
            letterSpacing: 1.5,
            fontSize: 13,
            color: Colors.white60,
          ),
        ),
      ],
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.step,
    required this.saving,
    required this.onNext,
    required this.onComplete,
  });
  final int step;
  final bool saving;
  final VoidCallback onNext;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: saving ? null : (step < 2 ? onNext : onComplete),
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  step < 2 ? Icons.arrow_forward_rounded : Icons.check_rounded,
                ),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(step < 2 ? 'Avanti' : 'Completa la registrazione'),
          ),
        ),
      ),
    ),
  );
}

class _Intro extends StatelessWidget {
  const _Intro({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(color: Colors.white70)),
      ],
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: sportFont,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        fontSize: 13,
        color: MilanacColors.gold,
      ),
    ),
  );
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
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3A2A08), Color(0xFF1A1A1A)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MilanacColors.gold.withValues(alpha: .6)),
      ),
      child: Row(
        children: [
          ClipOval(
            child: FaceView(
              face: face,
              size: 40,
              crop: FaceCrop.head,
              background: MilanacColors.surface,
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
                color: MilanacColors.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
