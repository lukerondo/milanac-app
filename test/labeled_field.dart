import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/features/auth/gate_ui.dart';

/// Il campo di testo con l'etichetta [label] sopra (accesso, registrazione, dati
/// personali: le etichette stanno fuori dal campo, come nelle tavole).
Finder labeledField(String label) => find.descendant(
  of: find.widgetWithText(LabeledField, label),
  matching: find.byType(TextField),
);
