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

class _LoginPageState extends ConsumerState<LoginPage> {
  LoginMethod? _busy;

  Future<void> _signIn(LoginMethod method) async {
    setState(() => _busy = method);
    try {
      await ref.read(authRepositoryProvider).signIn(method);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accesso non riuscito: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // "Accedi con Apple" è obbligatorio su iOS quando si offrono altri login social.
    final showApple = kIsWeb || defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Image.asset('assets/images/stemma.png', height: 140),
                  const SizedBox(height: 16),
                  const Text(
                    'MILANAC PRO CLUB',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: MilanacColors.gold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Milano siamo noi!', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 36),
                  _LoginButton(
                    label: 'Continua con Google',
                    icon: Icons.g_mobiledata_rounded,
                    busy: _busy == LoginMethod.google,
                    onPressed: _busy == null ? () => _signIn(LoginMethod.google) : null,
                  ),
                  _LoginButton(
                    label: 'Continua con Microsoft (Hotmail/Outlook)',
                    icon: Icons.window_rounded,
                    busy: _busy == LoginMethod.microsoft,
                    onPressed: _busy == null ? () => _signIn(LoginMethod.microsoft) : null,
                  ),
                  _LoginButton(
                    label: 'Continua con Yahoo',
                    icon: Icons.alternate_email_rounded,
                    busy: _busy == LoginMethod.yahoo,
                    onPressed: _busy == null ? () => _signIn(LoginMethod.yahoo) : null,
                  ),
                  if (showApple)
                    _LoginButton(
                      label: 'Continua con Apple',
                      icon: Icons.apple_rounded,
                      busy: _busy == LoginMethod.apple,
                      onPressed: _busy == null ? () => _signIn(LoginMethod.apple) : null,
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Dopo il primo accesso un membro del Direttivo approverà il tuo account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}
