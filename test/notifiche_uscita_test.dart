import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/core/push/push_service.dart';

/// FCM finto. Senza rete il token del telefono resta leggibile (è salvato sul telefono)
/// ma non si cancella; le uscite dagli argomenti FCM le tiene in coda da sé.
class _FakeFcm implements PushClient {
  bool online = true;
  var _token = 1;
  int deletes = 0;
  final topics = <String>[];
  final refresh = StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String?> getToken() async => 'T$_token';

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Future<void> subscribeToTopic(String topic) async => topics.add('+$topic');

  @override
  Future<void> unsubscribeFromTopic(String topic) async =>
      topics.add('-$topic');

  @override
  Future<void> deleteToken() async {
    deletes++;
    if (!online) throw Exception('SocketException: rete assente');
    _token++;
  }
}

/// Il server delle notifiche non si raggiunge (rete assente).
Future<void> _offline(String token) async =>
    throw Exception('SocketException: Failed host lookup');

void main() {
  test('uscita senza rete: il token resta da cancellare e si cancella appena si '
      'può', () async {
    final fcm = _FakeFcm();
    final push = PushService.test(fcm);
    addTearDown(push.dispose);
    final saved = <String>[];
    await push.subscribe(onToken: (t) async => saved.add(t));
    expect(saved, ['T1']);

    // Esce senza rete: la riga sul server resta e il token non si cancella, ma
    // l'uscita dall'argomento del club parte lo stesso (FCM la tiene in coda).
    fcm.online = false;
    await push.unsubscribe(onRemoveToken: _offline);
    expect(fcm.topics, ['+milanac', '-milanac']);
    expect(fcm.deletes, 1);
    expect(push.tokenCleanupPending, isTrue);

    // Ancora senza rete (ritorno in primo piano): niente da fare.
    await push.retryTokenCleanup();
    expect(fcm.deletes, 2);
    expect(push.tokenCleanupPending, isTrue);

    // Torna la rete: il token si cancella. FCM risponderà UNREGISTERED alla funzione
    // notify, che toglie la riga: le notifiche personali dell'account uscito non
    // arrivano più qui.
    fcm.online = true;
    await push.retryTokenCleanup();
    expect(fcm.deletes, 3);
    expect(push.tokenCleanupPending, isFalse);
    await push.retryTokenCleanup();
    expect(fcm.deletes, 3);

    // Il prossimo account entra con un token nuovo.
    await push.subscribe(onToken: (t) async => saved.add(t));
    expect(saved.last, 'T2');
  });

  test(
    'dopo un\'uscita senza rete entra un altro account: il token passa a lui e '
    'non si cancella più',
    () async {
      final fcm = _FakeFcm();
      final push = PushService.test(fcm);
      addTearDown(push.dispose);
      await push.subscribe(onToken: (_) async {});
      fcm.online = false;
      await push.unsubscribe(onRemoveToken: _offline);
      expect(push.tokenCleanupPending, isTrue);

      fcm.online = true;
      final saved = <String>[];
      await push.subscribe(onToken: (t) async => saved.add(t));
      // Lo stesso token, salvato per il nuovo account (la riga passa a lui).
      expect(saved, ['T1']);
      expect(push.tokenCleanupPending, isFalse);
      await push.retryTokenCleanup();
      expect(fcm.deletes, 1, reason: 'il token del nuovo account non si tocca');
    },
  );

  testWidgets('senza rete si riprova da solo ogni minuto', (tester) async {
    final fcm = _FakeFcm();
    final push = PushService.test(fcm);
    addTearDown(push.dispose);
    // Solo l'argomento del club: senza l'ascolto dei rinnovi del token, la cui
    // chiusura nel tempo finto dei test non finirebbe mai.
    await push.subscribe();
    fcm.online = false;
    await push.unsubscribe(onRemoveToken: _offline);
    expect(fcm.deletes, 1);

    await tester.pump(PushService.cleanupRetry);
    expect(fcm.deletes, 2);
    fcm.online = true;
    await tester.pump(PushService.cleanupRetry);
    expect(fcm.deletes, 3);
    expect(push.tokenCleanupPending, isFalse);
    await tester.pump(PushService.cleanupRetry * 3);
    expect(fcm.deletes, 3);
  });
}
