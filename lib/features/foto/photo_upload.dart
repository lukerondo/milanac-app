import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/haptics.dart';
import '../rosa/rosa_repository.dart';
import 'photo_frame.dart';

/// "Carica la tua foto": galleria, inquadratura nel riquadro della carta e caricamento al
/// posto di [previous]. Restituisce il percorso della foto nuova, null se annullato o
/// non riuscito (con il messaggio).
Future<String?> changeMemberPhoto(
  BuildContext context,
  WidgetRef ref, {
  required String memberId,
  String? previous,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(rosaRepositoryProvider);
  final jpeg = await pickCardPhoto(context);
  if (jpeg == null) return null;
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Carico la foto…'),
      duration: Duration(seconds: 20),
    ),
  );
  try {
    final path = await repo.uploadPhoto(memberId, jpeg, previous: previous);
    Haptics.confirm();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Foto aggiornata: ora è sulla tua carta.'),
        ),
      );
    return path;
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'Foto non caricata'))),
      );
    return null;
  }
}
