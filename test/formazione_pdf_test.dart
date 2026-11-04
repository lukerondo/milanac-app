import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/formazione/formation_pdf.dart';
import 'package:milanac/features/formazione/modules.dart';
import 'package:image/image.dart' as img;
import 'package:milanac/features/rosa/member.dart';

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
      'Donnarumma',
      'Calabria',
      'Tomori',
      'Thiaw',
      'Theo',
      'Bennacer',
      'Reijnders',
      'Loftus',
      'Pulisic',
      'Giroud',
      'Leao',
      'Maignan',
      'Florenzi',
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
        ),
    };
    final formation = Formation(
      team: Team.milanac,
      module: '4-3-3',
      players: {for (var i = 0; i < 11; i++) i: 'm$i'},
      // Chi batte: Giroud i rigori, Theo punizioni e angoli da sinistra, Pulisic
      // quelli da destra.
      setPieces: const {
        SetPiece.rigori: 'm9',
        SetPiece.punizioni: 'm4',
        SetPiece.angoliSinistra: 'm4',
        SetPiece.angoliDestra: 'm8',
      },
      publishedAt: DateTime(2026, 10, 10, 18),
    );
    expect(
      setPiecesPdfText(formation, members),
      'Rigori: Giroud · Punizioni: Theo · Angoli da sinistra: Theo · '
      'Angoli da destra: Pulisic',
    );
    expect(
      setPiecesPdfText(formation.copyWith(setPieces: const {}), members),
      isNull,
    );
    // Una foto vera per il primo titolare, la sagoma per gli altri.
    final photo = await decodeImageFromList(
      img.encodePng(
        img.Image(width: 72, height: 90)..clear(img.ColorRgb8(200, 30, 40)),
      ),
    );
    final image = await renderFormationImage(
      formation,
      members,
      photos: {'m0': photo},
    );
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

    // Con una panchina lunga e i battitori il campo si rimpicciolisce e tutto sta
    // nella pagina (nessun errore di impaginazione).
    final crowd = {
      ...members,
      for (var i = 0; i < 30; i++)
        'b$i': Member(
          id: 'b$i',
          displayName: 'Riserva con un nome lungo $i',
          role: ClubRole.giocatore,
          joinedAt: DateTime(2025, 9, 1),
        ),
    };
    final crowded = await buildFormationPdf(
      formation: formation,
      members: crowd,
      bench: [for (var i = 0; i < 30; i++) crowd['b$i']!],
      image: image,
      date: formation.publishedAt,
    );
    expect(String.fromCharCodes(crowded.take(4)), '%PDF');

    // Copia per chi vuole vederli (fuori dal repository).
    final dir = Directory('${Directory.systemTemp.path}/milanac_formazione')
      ..createSync(recursive: true);
    File('${dir.path}/formazione.png').writeAsBytesSync(image);
    File('${dir.path}/formazione.pdf').writeAsBytesSync(pdf);
  });
}
