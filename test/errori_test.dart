import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/core/errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  test('limite della tabella superato: il messaggio è in italiano, non quello '
      'grezzo di Postgres', () {
    const check = PostgrestException(
      message:
          'new row for relation "tournaments" violates check constraint '
          '"tournaments_name_check"',
      code: '23514',
    );
    expect(
      friendlyError(check, action: 'Salvataggio non riuscito'),
      'Salvataggio non riuscito: un campo è troppo lungo o non valido.',
    );
    // Anche un testo troppo lungo per la colonna e un numero fuori misura.
    for (final code in ['22001', '22003']) {
      expect(
        friendlyError(
          PostgrestException(message: 'value too long', code: code),
        ),
        'Operazione non riuscita: un campo è troppo lungo o non valido.',
      );
    }
    // Le regole del database che parlano già italiano restano come sono.
    expect(
      friendlyError(
        const PostgrestException(
          message: 'Il bonus va da +1 a +5',
          code: 'P0001',
        ),
      ),
      'Il bonus va da +1 a +5',
    );
  });
}
