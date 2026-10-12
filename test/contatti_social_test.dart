import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/shared/club_links.dart';
import 'package:milanac/shared/club_links_editor.dart';

/// Contatti che non arrivano finché [fail] è vero (rete assente).
class _FlakyLinks implements ClubLinksRepository {
  var fail = true;
  List<ClubLink>? saved;

  /// Quelli sul server.
  var links = const [
    ClubLink(kind: LinkKind.instagram, url: 'https://instagram.com/milanac'),
  ];

  @override
  Future<List<ClubLink>> load() async {
    if (fail) throw Exception('rete assente');
    return links;
  }

  @override
  Future<void> saveAll(List<ClubLink> links) async => saved = links;
}

void main() {
  testWidgets('Contatti social: con il caricamento fallito non si salva '
      '(cancellerebbe tutti i contatti)', (tester) async {
    final repo = _FlakyLinks();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [clubLinksRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute(
                  // Il menu non aveva i contatti: l'editor riceve un elenco vuoto.
                  builder: (_) => const ClubLinksEditorPage(initial: []),
                ),
              ),
              child: const Text('Apri'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();

    expect(find.text('Riprova'), findsOneWidget);
    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'SALVA'),
    );
    expect(save.onPressed, isNull);
    expect(find.byType(FloatingActionButton), findsNothing);

    // Torna la rete: i contatti arrivano e il salvataggio li conserva.
    repo.fail = false;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('https://instagram.com/milanac'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'SALVA'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    expect(repo.saved!.single.url, 'https://instagram.com/milanac');
    expect(find.text('Apri'), findsOneWidget);
  });

  testWidgets('Contatti social: l\'editor parte da quelli del server, non da '
      'quelli che la pagina Club ha in memoria', (tester) async {
    final repo = _FlakyLinks()..fail = false;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [clubLinksRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    // La pagina Club li ha già letti.
    container.listen(clubLinksProvider, (_, _) {});
    await container.read(clubLinksProvider.future);
    // Un altro telefono del Direttivo aggiunge WhatsApp.
    repo.links = const [
      ClubLink(kind: LinkKind.instagram, url: 'https://instagram.com/milanac'),
      ClubLink(kind: LinkKind.whatsapp, url: 'https://wa.me/39333'),
    ];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ClubLinksEditorPage(initial: [])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('https://wa.me/39333'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'SALVA'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(2));
  });
}
