import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/teams.dart';
import '../rosa/member.dart';
import '../volto/face.dart';

/// I dati raccolti nei tre passi della registrazione.
class RegistrationData {
  const RegistrationData({
    required this.firstName,
    required this.lastName,
    required this.birthYear,
    required this.cardName,
    required this.motto,
    required this.teams,
    required this.direttivo,
    required this.direttivoPassword,
    required this.direttivoRoles,
    required this.fieldPosition,
    required this.shirtNumber,
    required this.platform,
    required this.face,
  });

  final String firstName;
  final String lastName;
  final int birthYear;
  final String cardName;
  final String? motto;
  final Set<Team> teams;
  final bool direttivo;
  final String? direttivoPassword;
  final List<DirettivoRole> direttivoRoles;
  final String fieldPosition;
  final int? shirtNumber;
  final GamePlatform? platform;
  final Face face;

  Map<String, dynamic> toParams() => {
    'p_first_name': firstName,
    'p_last_name': lastName,
    'p_birth_year': birthYear,
    'p_display_name': cardName,
    'p_motto': motto,
    'p_teams': teamsToJson(teams),
    'p_direttivo': direttivo,
    'p_direttivo_password': direttivo ? direttivoPassword : null,
    'p_direttivo_roles': direttivo
        ? [for (final r in direttivoRoles) r.name]
        : <String>[],
    'p_field_position': fieldPosition,
    'p_shirt_number': shirtNumber,
    'p_platform': platform?.name,
    'p_face': face.toJson(),
  };
}

abstract class RegistrationRepository {
  /// Salva i dati (funzione `complete_registration`); il ruolo arriva accettando il regolamento.
  Future<void> complete(RegistrationData data);
}

final registrationRepositoryProvider = Provider<RegistrationRepository>((ref) {
  if (AppConfig.isDemo) return DemoRegistrationRepository();
  return _SupabaseRegistrationRepository(ref);
});

class _SupabaseRegistrationRepository implements RegistrationRepository {
  _SupabaseRegistrationRepository(this._ref);
  final Ref _ref;

  @override
  Future<void> complete(RegistrationData data) async {
    await _ref
        .read(supabaseProvider)
        .rpc('complete_registration', params: data.toParams());
  }
}

class DemoRegistrationRepository implements RegistrationRepository {
  RegistrationData? last;

  @override
  Future<void> complete(RegistrationData data) async => last = data;
}

/// Testo comprensibile per gli errori della registrazione (le regole del database
/// parlano già italiano: "Password del Direttivo non corretta", ...).
String friendlyRegistrationError(Object e) {
  if (e is PostgrestException) return e.message;
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup')) {
    return 'Nessuna connessione: controlla la rete e riprova.';
  }
  return 'Salvataggio non riuscito: $s';
}
