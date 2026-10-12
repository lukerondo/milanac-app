import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_flags.dart';

/// Aspetto scelto in Impostazioni: scuro (predefinito), chiaro o automatico (come il
/// telefono). Etichette corte: le tre stanno affiancate anche su un telefono stretto.
enum Appearance {
  scuro('Scuro', ThemeMode.dark),
  chiaro('Chiaro', ThemeMode.light),
  sistema('Automatico', ThemeMode.system);

  const Appearance(this.label, this.mode);
  final String label;
  final ThemeMode mode;

  static Appearance parse(String? v) =>
      values.firstWhere((a) => a.name == v, orElse: () => Appearance.scuro);
}

final appearanceProvider = NotifierProvider<AppearanceNotifier, Appearance>(
  AppearanceNotifier.new,
);

class AppearanceNotifier extends Notifier<Appearance> {
  static const _key = 'aspetto';

  /// Scelta fatta in questa sessione: la lettura iniziale, se arriva dopo, non la copre.
  var _chosen = false;

  @override
  Appearance build() {
    // Il tema salvato arriva un attimo dopo l'avvio: fino ad allora vale lo scuro.
    ref.read(localFlagsProvider).getString(_key).then((v) {
      final saved = Appearance.parse(v);
      if (ref.mounted && !_chosen && saved != state) state = saved;
    }).ignore();
    return Appearance.scuro;
  }

  Future<void> set(Appearance a) async {
    _chosen = true;
    state = a;
    await ref.read(localFlagsProvider).setString(_key, a.name);
  }
}
