// La registrazione nel browser resta in memoria: si legge dall'indirizzo `blob:` e poi
// si libera. Gira solo in un browser: flutter test --platform chrome test/web
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/features/chat/chat_repository.dart' show audioFormatOf;
import 'package:milanac/features/chat/voice_file_web.dart';

@JS('eval')
external JSString _eval(String code);

void main() {
  test(
    'si leggono i byte della registrazione, poi la memoria si libera',
    () async {
      // Un "WAV" di prova, come lo consegna il registratore del browser.
      final url = _eval('''
      URL.createObjectURL(new Blob(
        [new Uint8Array([82, 73, 70, 70, 4, 0, 0, 0, 87, 65, 86, 69, 1, 2, 3, 4])],
        { type: "audio/wav" }))
    ''').toDart;
      expect(url, startsWith('blob:'));
      final bytes = await readRecording(url);
      expect(
        bytes,
        Uint8List.fromList([
          82,
          73,
          70,
          70,
          4,
          0,
          0,
          0,
          87,
          65,
          86,
          69,
          1,
          2,
          3,
          4,
        ]),
      );
      expect(audioFormatOf(bytes), ('wav', 'audio/wav'));

      await discardRecording(url);
      await expectLater(readRecording(url), throwsA(anything));
      // Nel browser non c'è un file in cui registrare.
      expect(await recordingPath('vocale.m4a'), '');
    },
  );
}
