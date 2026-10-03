import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config.dart';
import '../regolamento/regolamento_page.dart';

/// Informativa sulla privacy (stesso testo da pubblicare per gli store).
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PRIVACY')),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('assets/legal/privacy.md'),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final email = AppConfig.contactEmail.isEmpty
              ? 'da-configurare@milanac.it'
              : AppConfig.contactEmail;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SimpleRichText(snap.data!.replaceAll('{{EMAIL}}', email)),
          );
        },
      ),
    );
  }
}
