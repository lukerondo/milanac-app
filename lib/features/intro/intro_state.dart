import 'package:flutter_riverpod/flutter_riverpod.dart';

/// true quando l'intro è terminata (o saltata).
final introDoneProvider = NotifierProvider<IntroDone, bool>(IntroDone.new);

class IntroDone extends Notifier<bool> {
  @override
  bool build() => false;

  void complete() => state = true;
}
