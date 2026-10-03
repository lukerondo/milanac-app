import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/providers.dart';
import 'core/config.dart';
import 'core/push/device_tokens.dart';
import 'core/push/push_service.dart';
import 'core/router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it');
  if (!AppConfig.isDemo) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }
  await PushService.instance.init();
  runApp(const ProviderScope(child: MilanacApp()));
}

class MilanacApp extends ConsumerWidget {
  const MilanacApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    PushService.instance.onOpenRoute = router.go;

    // Notifiche del club solo per i membri approvati.
    ref.listen(profileProvider, (_, next) {
      final profile = next.value;
      final tokens = ref.read(deviceTokensProvider);
      if (profile?.isApproved ?? false) {
        PushService.instance.subscribe(onToken: tokens.save);
      } else if (next.hasValue && profile == null) {
        PushService.instance.unsubscribe(onRemoveToken: tokens.remove);
      }
    });

    return MaterialApp.router(
      title: 'MILANAC Pro Club',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
      scaffoldMessengerKey: messengerKey,
      locale: const Locale('it'),
      supportedLocales: const [Locale('it'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
