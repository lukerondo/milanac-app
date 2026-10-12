import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/shared/club_links.dart';
import 'package:milanac/shared/club_links_editor.dart';

/// Contatti che non arrivano finché [fail] è vero (rete assente).
class _FlakyLinks implements ClubLinksRepository {
  var fail = true;
  List<ClubLink>? saved;

  @override
  Future<List<ClubLink>> load() async {
    if (fail) throw Exception('rete assente');
    return const [
      ClubLink(kind: LinkKind.instagram, url: 'https://instagram.com/milanac'),
    ];
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
}
