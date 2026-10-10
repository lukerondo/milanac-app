import 'dart:io';
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/formazione/formation_pdf.dart';
import 'package:milanac/features/formazione/modules.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/features/volto/face.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('it'));

  test('formazione: immagine con le mini carte e PDF', () async {
    // Nei test il carattere predefinito è un segnaposto: carica Oswald per davvero.
    final fonts = FontLoader('Oswald');
    for (final w in ['400', '500', '600', '700']) {
      fonts.addFont(rootBundle.load('assets/fonts/Oswald-$w.ttf'));
    }
    await fonts.load();

    const names = [
      'Donnarumma', 'Calabria', 'Tomori', 'Thiaw', 'Theo', 'Bennacer',
      'Reijnders', 'Loftus', 'Pulisic', 'Giroud', 'Leao', 'Maignan', 'Florenzi',
    ];
    final members = {
      for (final (i, n) in names.indexed)
        'm$i': Member(
          id: 'm$i',
          displayName: n,
          role: i == 0 ? ClubRole.direttivo : ClubRole.giocatore,
          joinedAt: DateTime(2025, 9, 1),
          overall: 60 + (i * 3) % 32,
          fieldPosition: 'CC',
          face: Face.random(Random(i)),
        ),
    };
    final formation = Formation(
      team: Team.milanac,
      module: '4-3-3',
      players: {for (var i = 0; i < 11; i++) i: 'm$i'},
      publishedAt: DateTime(2026, 10, 10, 18),
    );
    final image = await renderFormationImage(formation, members);
    expect(image.length, greaterThan(10000));
    final decoded = await decodeImageFromList(image);
    expect(decoded.width, 1080);
    expect(decoded.height, (1080 / 0.68).round());

    final pdf = await buildFormationPdf(
      formation: formation,
      members: members,
      bench: [members['m11']!, members['m12']!],
      image: image,
      date: formation.publishedAt,
    );
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');

    // Copia per chi vuole vederli (fuori dal repository).
    final dir = Directory('${Directory.systemTemp.path}/milanac_formazione')
      ..createSync(recursive: true);
    File('${dir.path}/formazione.png').writeAsBytesSync(image);
    File('${dir.path}/formazione.pdf').writeAsBytesSync(pdf);
  });
}
