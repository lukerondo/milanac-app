import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_flags.dart';

/// Le vibrazioni dell'app, tutte da qui: si spengono da Impostazioni → Aspetto →
/// Vibrazioni. Tocco, colpi leggeri, medi e forti; [confirm] quando una cosa è fatta
/// (risposta alle presenze, partita salvata...), [goal] per un gol o una vittoria.
abstract final class Haptics {
  /// Acceso di serie; lo tiene aggiornato [vibrationsProvider].
  static bool enabled = true;

  static Future<void> tap() =>
      enabled ? HapticFeedback.selectionClick() : Future.value();
  static Future<void> light() =>
      enabled ? HapticFeedback.lightImpact() : Future.value();
  static Future<void> medium() =>
      enabled ? HapticFeedback.mediumImpact() : Future.value();
  static Future<void> heavy() =>
      enabled ? HapticFeedback.heavyImpact() : Future.value();

  /// Fatto: risposta salvata, partita salvata, carte assegnate.
  static Future<void> confirm() => medium();

  /// Gol, vittoria: il colpo più forte.
  static Future<void> goal() => heavy();
}

/// Vibrazioni accese (predefinito) o spente, salvate sul telefono.
final vibrationsProvider = NotifierProvider<VibrationsNotifier, bool>(
  VibrationsNotifier.new,
);

class VibrationsNotifier extends Notifier<bool> {
  static const _key = 'vibrazioni';

  /// Scelta fatta in questa sessione: la lettura iniziale, se arriva dopo, non la copre.
  var _chosen = false;

  @override
  bool build() {
    ref.read(localFlagsProvider).getString(_key).then((v) {
      if (!ref.mounted || _chosen || v == null) return;
      state = Haptics.enabled = v != 'no';
    }).ignore();
    return Haptics.enabled = true;
  }

  Future<void> set(bool on) async {
    _chosen = true;
    state = Haptics.enabled = on;
    if (on) await Haptics.tap();
    await ref.read(localFlagsProvider).setString(_key, on ? 'si' : 'no');
  }
}
