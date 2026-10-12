import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/push/device_tokens.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import 'gate_ui.dart';

/// Dopo il link "password dimenticata": scelta della nuova password.
class NewPasswordPage extends ConsumerStatefulWidget {
  const NewPasswordPage({super.key});

  @override
  ConsumerState<NewPasswordPage> createState() => _NewPasswordPageState();
}

class _NewPasswordPageState extends ConsumerState<NewPasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _hidden = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_password.text.length < 8) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('La password deve avere almeno 8 caratteri.'),
        ),
      );
      return;
    }
    if (_password.text != _confirm.text) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Le due password non coincidono.')),
      );
      return;
    }
    setState(() => _saving = true);
    final recovery = ref.read(passwordRecoveryProvider.notifier);
    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      recovery.done();
      messenger.showSnackBar(
        const SnackBar(content: Text('Password aggiornata.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyAuthError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: gateAppBar(
        title: 'NUOVA PASSWORD',
        automaticallyImplyLeading: false,
        actions: [
          if (!AppConfig.isDemo)
            IconButton(
              tooltip: 'Esci dall\'account',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => logout(ref),
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: IconTile(Icons.lock_reset_rounded, size: 64)),
                  const SizedBox(height: 16),
                  const Center(
                    child: GateTitle('Scegli la nuova password', size: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Il link dell\'email ti ha fatto entrare: scegli la password che '
                    'userai d\'ora in poi per accedere.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  LabeledField(
                    label: 'Nuova password (almeno 8 caratteri)',
                    child: TextField(
                      controller: _password,
                      obscureText: _hidden,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        suffixIcon: ShowPasswordButton(
                          hidden: _hidden,
                          onPressed: () => setState(() => _hidden = !_hidden),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'Ripeti la password',
                    child: TextField(
                      controller: _confirm,
                      obscureText: _hidden,
                      onSubmitted: (_) => _saving ? null : _save(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Salva la password',
                    busy: _saving,
                    onPressed: _save,
                  ),
                  const SizedBox(height: 4),
                  // Il link ha già fatto entrare: si può tenere la password attuale.
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => ref
                              .read(passwordRecoveryProvider.notifier)
                              .done(),
                    child: const Text('Annulla'),
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
