import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/providers.dart';
import '../../core/theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

enum _EmailMode { signIn, signUp }

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  LoginMethod? _busy;
  bool _emailBusy = false;
  bool _hidden = true;
  _EmailMode _mode = _EmailMode.signIn;

  /// Email a cui è stato inviato il link di conferma (mostra l'avviso di attesa).
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
    setState(() => _emailBusy = true);
    final auth = ref.read(authRepositoryProvider);
    try {
      if (_mode == _EmailMode.signIn) {
        await auth.signInWithEmail(_email.text, _password.text);
      } else {
        final result = await auth.signUpWithEmail(_email.text, _password.text);
        if (result == EmailSignUpResult.needsConfirmation && mounted) {
          setState(() => _sentTo = _email.text.trim());
        }
      }
    } catch (e) {
      if (mounted) _toast(friendlyAuthError(e));
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
    // "Accedi con Apple" è obbligatorio su iOS quando si offrono altri login social.
    final showApple =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final busy = _busy != null || _emailBusy;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Sfondo della vecchia app: stemma del club e Duomo in oro.
          Image.asset(
            'assets/images/login_bg.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Color(0xB3000000),
                  Color(0xF5000000),
                ],
                stops: [.25, .5, 1],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 200, 24, 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'MILANO SIAMO NOI!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: sportFont,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 3,
                            color: MilanacColors.gold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_sentTo != null)
                          _EmailSentNotice(
                            email: _sentTo!,
                            onResend: _resend,
                            onChange: () => setState(() => _sentTo = null),
                          )
                        else ...[
                          _SocialRow(
                            busy: _busy,
                            enabled: !busy,
                            showApple: showApple,
                            onPressed: _signIn,
                          ),
                          const SizedBox(height: 14),
                          const _OrDivider('oppure con la tua email'),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _password,
                            obscureText: _hidden,
                            autofillHints: [
                              _mode == _EmailMode.signIn
                                  ? AutofillHints.password
                                  : AutofillHints.newPassword,
                            ],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => busy ? null : _submitEmail(),
                            decoration: InputDecoration(
                              labelText: _mode == _EmailMode.signIn
                                  ? 'Password'
                                  : 'Password (almeno 8 caratteri)',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _hidden ? 'Mostra' : 'Nascondi',
                                icon: Icon(
                                  _hidden
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                ),
                                onPressed: () =>
                                    setState(() => _hidden = !_hidden),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: busy ? null : _submitEmail,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: _emailBusy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _mode == _EmailMode.signIn
                                          ? 'Accedi'
                                          : 'Crea il mio account',
                                    ),
                            ),
                          ),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () => setState(
                                  () => _mode = _mode == _EmailMode.signIn
                                      ? _EmailMode.signUp
                                      : _EmailMode.signIn,
                                ),
                                child: Text(
                                  _mode == _EmailMode.signIn
                                      ? 'Non hai un account? Registrati'
                                      : 'Hai già un account? Accedi',
                                ),
                              ),
                              if (_mode == _EmailMode.signIn)
                                TextButton(
                                  onPressed: busy ? null : _forgotPassword,
                                  child: const Text('Password dimenticata?'),
                                ),
                            ],
                          ),
                          const Text(
                            'Al primo accesso completi il profilo, crei il tuo volto e accetti il regolamento.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// I quattro accessi social su due righe.
class _SocialRow extends StatelessWidget {
  const _SocialRow({
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
    final items = [
      (LoginMethod.google, 'Google', Icons.g_mobiledata_rounded),
      (LoginMethod.microsoft, 'Microsoft', Icons.window_rounded),
      (LoginMethod.yahoo, 'Yahoo', Icons.alternate_email_rounded),
      if (showApple) (LoginMethod.apple, 'Apple', Icons.apple_rounded),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (method, label, icon) in items)
              SizedBox(
                width: width,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: enabled ? () => onPressed(method) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: busy == method
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(icon),
                  label: Text(label),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider(color: Colors.white24)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ),
      const Expanded(child: Divider(color: Colors.white24)),
    ],
  );
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: MilanacColors.gold.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: MilanacColors.gold.withValues(alpha: .5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_rounded,
          color: MilanacColors.gold,
          size: 40,
        ),
        const SizedBox(height: 10),
        Text(
          'Controlla la tua email',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Abbiamo inviato un link a $email. Aprilo dal telefono per confermare '
          'l\'account: l\'app si aprirà da sola sulla registrazione.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: onResend,
          child: const Text('Invia di nuovo l\'email'),
        ),
        TextButton(
          onPressed: onChange,
          child: const Text('Usa un\'altra email'),
        ),
      ],
    ),
  );
}
