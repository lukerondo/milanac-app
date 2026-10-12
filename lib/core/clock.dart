import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L'ora corrente (un istante): nei test si sostituisce con un orario fisso
/// (le presenze cambiano comportamento alle 18:30). Per "oggi", la scadenza delle
/// risposte e gli orari mostrati si passa all'ora italiana (vedi italian_time.dart).
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);
