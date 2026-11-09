import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/providers.dart';
import '../../core/auth/signup_gate.dart';
import '../../core/theme.dart';
import '../../shared/gold_loader.dart';
import '../../shared/ui.dart';
import 'gate_ui.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

enum _EmailMode { signIn, signUp }

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _clubPassword = TextEditingController();
  LoginMethod? _busy;
  bool _emailBusy = false;
  bool _hidden = true;
  bool _clubHidden = true;

  /// Password del club rifiutata dal server: evidenziata sul campo.
  String? _clubError;
  _EmailMode _mode = _EmailMode.signIn;

  /// Email a cui è stato inviato il link di conferma (mostra l'avviso di attesa).
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _clubPassword.dispose();
    super.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _signIn(LoginMethod method) async {
    setState(() => _busy = method);
    try {
      await ref.read(authRepositoryProvider).signIn(method);
    } catch (e) {
      if (mounted) _toast(friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  bool _validEmail() {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      _toast('Scrivi un indirizzo email valido.');
      return false;
    }
    return true;
  }

  Future<void> _submitEmail() async {
    if (!_validEmail()) return;
    if (_password.text.length < 8) {
      _toast('La password deve avere almeno 8 caratteri.');
      return;
    }
    final signUp = _mode == _EmailMode.signUp;
    // Per creare un account serve la password del club (se il Direttivo l'ha impostata).
    final needsClubPassword =
        signUp && ref.read(signupStatusProvider).value == SignupStatus.password;
    if (needsClubPassword && _clubPassword.text.isEmpty) {
      _toast('Scrivi la password del club: te la dà il Direttivo.');
      return;
    }
    setState(() => _emailBusy = true);
    final auth = ref.read(authRepositoryProvider);
    try {
      if (!signUp) {
        await auth.signInWithEmail(_email.text, _password.text);
      } else {
        if (needsClubPassword) {
          await ref
              .read(signupGateRepositoryProvider)
              .requestSignup(_email.text, _clubPassword.text);
        }
        final result = await auth.signUpWithEmail(_email.text, _password.text);
        if (!mounted) return;
        switch (result) {
          case EmailSignUpResult.needsConfirmation:
            setState(() => _sentTo = _email.text.trim());
          case EmailSignUpResult.alreadyRegistered:
            // Nessuna email inviata: si passa all'accesso (con "Password dimenticata?").
            setState(() => _mode = _EmailMode.signIn);
            _toast(alreadyRegisteredText);
          case EmailSignUpResult.signedIn:
          // Conferma dell'email disattivata: si entra subito, prosegue il router.
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (isClubPasswordError(e)) {
        setState(() => _clubError = friendlyAuthError(e));
        // Le iscrizioni possono essere state chiuse nel frattempo: si rilegge lo stato.
        ref.invalidate(signupStatusProvider);
      }
      _toast(friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _emailBusy = false);
    }
  }

  Future<void> _forgotPassword() async {
    if (!_validEmail()) return;
    setState(() => _emailBusy = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) {
        _toast(
          'Ti abbiamo inviato un\'email: apri il link per scegliere una nuova password.',
        );
      }
    } catch (e) {
      if (mounted) _toast(friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _emailBusy = false);
    }
  }

  Future<void> _resend() async {
    final email = _sentTo;
    if (email == null) return;
    try {
      await ref.read(authRepositoryProvider).resendConfirmation(email);
      if (mounted) _toast('Email inviata di nuovo a $email.');
    } catch (e) {
      if (mounted) _toast(friendlyAuthError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // "Accedi con Apple" è obbligatorio su iOS quando si offrono altri login social.
    final showApple =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final signUp = _mode == _EmailMode.signUp;
    // Solo creando un account: serve la password del club, o le iscrizioni sono chiuse.
    final gate = signUp ? ref.watch(signupStatusProvider) : null;
    // Stato non arrivato (rete): si mostra il campo, tanto decide il server.
    final clubPassword =
        gate != null &&
        (gate.value == SignupStatus.password ||
            gate.hasError && !gate.hasValue);
    final closed = gate?.value == SignupStatus.closed;
    final busy =
        _busy != null ||
        _emailBusy ||
        (gate?.isLoading ?? false) && !gate!.hasValue;
    void switchMode() =>
        setState(() => _mode = signUp ? _EmailMode.signIn : _EmailMode.signUp);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Crest(),
                        const _GoldFade(),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_sentTo != null)
                                  _EmailSentNotice(
                                    email: _sentTo!,
                                    onResend: _resend,
                                    onChange: () =>
                                        setState(() => _sentTo = null),
                                  )
                                else if (closed)
                                  const _SignupsClosedNotice()
                                else ...[
                                  GateTitle(
                                    signUp ? 'Crea il tuo account' : 'Accedi',
                                    size: 26,
                                  ),
                                  const SizedBox(height: 14),
                                  LabeledField(
                                    label: 'Email',
                                    child: TextField(
                                      controller: _email,
                                      keyboardType: TextInputType.emailAddress,
                                      autocorrect: false,
                                      autofillHints: const [
                                        AutofillHints.email,
                                      ],
                                      textInputAction: TextInputAction.next,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  LabeledField(
                                    label: signUp
                                        ? 'Password (almeno 8 caratteri)'
                                        : 'Password',
                                    child: TextField(
                                      controller: _password,
                                      obscureText: _hidden,
                                      autofillHints: [
                                        signUp
                                            ? AutofillHints.newPassword
                                            : AutofillHints.password,
                                      ],
                                      textInputAction: clubPassword
                                          ? TextInputAction.next
                                          : TextInputAction.done,
                                      onSubmitted: (_) => busy || clubPassword
                                          ? null
                                          : _submitEmail(),
                                      decoration: InputDecoration(
                                        suffixIcon: ShowPasswordButton(
                                          hidden: _hidden,
                                          onPressed: () => setState(
                                            () => _hidden = !_hidden,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (!signUp)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: busy
                                            ? null
                                            : _forgotPassword,
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          textStyle: const TextStyle(
                                            fontFamily: bodyFont,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        child: const Text(
                                          'Password dimenticata?',
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox(height: 12),
                                  if (clubPassword) ...[
                                    LabeledField(
                                      label: 'Password del club',
                                      help:
                                          'Te la dà il Direttivo: serve una volta '
                                          'sola, per creare l\'account.',
                                      child: TextField(
                                        controller: _clubPassword,
                                        obscureText: _clubHidden,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        textInputAction: TextInputAction.done,
                                        onChanged: (_) {
                                          if (_clubError != null) {
                                            setState(() => _clubError = null);
                                          }
                                        },
                                        onSubmitted: (_) =>
                                            busy ? null : _submitEmail(),
                                        decoration: InputDecoration(
                                          errorText: _clubError,
                                          errorMaxLines: 3,
                                          suffixIcon: ShowPasswordButton(
                                            hidden: _clubHidden,
                                            onPressed: () => setState(
                                              () => _clubHidden = !_clubHidden,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  const SizedBox(height: 4),
                                  PrimaryButton(
                                    label: signUp
                                        ? 'Crea il mio account'
                                        : 'Accedi',
                                    busy: _emailBusy,
                                    onPressed: busy ? null : _submitEmail,
                                  ),
                                  const SizedBox(height: 16),
                                  const _OrDivider('oppure'),
                                  const SizedBox(height: 16),
                                  _SocialButtons(
                                    busy: _busy,
                                    enabled: !busy,
                                    showApple: showApple,
                                    onPressed: _signIn,
                                  ),
                                  if (signUp) ...[
                                    const SizedBox(height: 14),
                                    Text(
                                      'Al primo accesso completi il profilo, carichi la '
                                      'tua foto e accetti il regolamento.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: p.textMuted,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ],
                                const Spacer(),
                                const SizedBox(height: 16),
                                if (_sentTo == null)
                                  // A capo se non ci sta (schermi stretti, testo grande).
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        signUp
                                            ? 'Hai già un account?'
                                            : 'Nuovo nel club?',
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: 15,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: busy ? null : switchMode,
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                          ),
                                        ),
                                        child: Text(
                                          signUp ? 'Accedi' : 'Registrati',
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Al posto del modulo quando il Direttivo non ha impostato la password del club.
class _SignupsClosedNotice extends StatelessWidget {
  const _SignupsClosedNotice();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GateTitle('Iscrizioni chiuse', size: 26),
        const SizedBox(height: 12),
        Text(
          'Per entrare nel club serve la password di iscrizione, che il Direttivo '
          'non ha ancora impostato. Chiedi a chi ti ha invitato e riprova più tardi.',
          style: TextStyle(color: p.textSecondary, fontSize: 16, height: 1.4),
        ),
      ],
    );
  }
}

/// Stemma e nome del club, in alto.
class _Crest extends StatelessWidget {
  const _Crest();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 40, 24, 22),
    child: Column(
      children: [
        Image.asset(
          'assets/images/stemma_256.png',
          height: 112,
          filterQuality: FilterQuality.high,
          semanticLabel: 'Stemma MILANAC Pro Club',
        ),
        const SizedBox(height: 10),
        Text(
          'MILANAC PRO CLUB',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: sportFont,
            fontWeight: FontWeight.w600,
            fontSize: 24,
            letterSpacing: 2.9,
            color: context.pal.accentText,
          ),
        ),
      ],
    ),
  );
}

/// Filo d'oro che sfuma ai lati, sotto il nome del club.
class _GoldFade extends StatelessWidget {
  const _GoldFade();

  @override
  Widget build(BuildContext context) {
    final gold = context.pal.accentText;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: 2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                gold.withValues(alpha: 0),
                gold,
                gold.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Accessi social: Google su tutta la riga, gli altri sotto.
class _SocialButtons extends StatelessWidget {
  const _SocialButtons({
    required this.busy,
    required this.enabled,
    required this.showApple,
    required this.onPressed,
  });
  final LoginMethod? busy;
  final bool enabled;
  final bool showApple;
  final ValueChanged<LoginMethod> onPressed;

  @override
  Widget build(BuildContext context) {
    final others = [
      (LoginMethod.microsoft, 'Microsoft'),
      if (showApple) (LoginMethod.apple, 'Apple'),
      (LoginMethod.yahoo, 'Yahoo'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SocialButton(
          label: 'Continua con Google',
          busy: busy == LoginMethod.google,
          onPressed: enabled ? () => onPressed(LoginMethod.google) : null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (i, (method, label)) in others.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _SocialButton(
                  label: label,
                  fontSize: 15,
                  busy: busy == method,
                  onPressed: enabled ? () => onPressed(method) : null,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.busy,
    required this.onPressed,
    this.fontSize = 16,
  });
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        backgroundColor: p.surface,
        foregroundColor: p.text,
        side: BorderSide(color: p.borderStrong, width: 1.5),
        textStyle: TextStyle(
          fontFamily: bodyFont,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: busy
          ? const SizedBox(width: 18, height: 18, child: GoldLoader(size: 18))
          : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        Expanded(child: Divider(color: p.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text, style: TextStyle(color: p.textMuted, fontSize: 14)),
        ),
        Expanded(child: Divider(color: p.border)),
      ],
    );
  }
}

/// Dopo la registrazione con email: si entra solo aprendo il link ricevuto.
class _EmailSentNotice extends StatelessWidget {
  const _EmailSentNotice({
    required this.email,
    required this.onResend,
    required this.onChange,
  });
  final String email;
  final VoidCallback onResend;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      important: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.mark_email_read_rounded, color: p.accentText, size: 40),
          const SizedBox(height: 10),
          Text(
            'Controlla la tua email',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: sportFont,
              fontWeight: FontWeight.w600,
              fontSize: 20,
              letterSpacing: .5,
              color: p.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Abbiamo inviato un link a $email. Aprilo dal telefono per confermare '
            'l\'account: l\'app si aprirà da sola sulla registrazione.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 14),
          PrimaryButton(label: 'Invia di nuovo l\'email', onPressed: onResend),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onChange,
            child: const Text('Usa un\'altra email'),
          ),
        ],
      ),
    );
  }
}
