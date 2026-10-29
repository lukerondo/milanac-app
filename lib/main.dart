import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/appearance.dart';
import 'core/auth/providers.dart';
import 'core/config.dart';
import 'core/errors.dart';
import 'core/haptics.dart';
import 'core/push/device_tokens.dart';
import 'core/push/push_service.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/musica/soundtrack.dart';

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
  // Dati dal server: nuovi tentativi senza arrendersi quando la rete va e viene.
  runApp(const ProviderScope(retry: retryForever, child: MilanacApp()));
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

    // Musica di sottofondo: resta attiva per tutta la vita dell'app.
    ref.listen(soundtrackProvider, (_, _) {});
    // Vibrazioni accese o spente (scelta salvata sul telefono).
    ref.listen(vibrationsProvider, (_, _) {});

    return MaterialApp.router(
      title: 'MILANAC Pro Club',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(appearanceProvider).mode,
      routerConfig: router,
      scaffoldMessengerKey: messengerKey,
      locale: const Locale('it'),
      supportedLocales: const [Locale('it'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
