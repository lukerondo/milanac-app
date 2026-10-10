import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L'ora corrente: nei test si sostituisce con un orario fisso
/// (le presenze cambiano comportamento alle 18:30).
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);
