import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config.dart';
import '../../shared/app_shell.dart';
import '../auth/gate_ui.dart';
import '../regolamento/regolamento_page.dart';

/// Informativa sulla privacy (stesso testo da pubblicare per gli store).
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gateAppBar(title: 'PRIVACY', divider: true),
      body: ContentWidth(
        child: FutureBuilder<String>(
          future: rootBundle.loadString('assets/legal/privacy.md'),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final email = AppConfig.contactEmail.isEmpty
                ? 'da-configurare@milanac.it'
                : AppConfig.contactEmail;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: SimpleRichText(snap.data!.replaceAll('{{EMAIL}}', email)),
            );
          },
        ),
      ),
    );
  }
}
