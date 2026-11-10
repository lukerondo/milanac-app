import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/auth/signup_gate.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/teams.dart';
import '../rosa/member.dart';

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
    this.clubPassword = '',
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

  /// Password di iscrizione al club: la scrive qui chi non l'ha data creando l'account
  /// (login social, account nati prima della regola). Vuota se non serve.
  final String clubPassword;

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
    // Il volto disegnato non c'è più: la foto si carica a parte (passo 3). Il
    // parametro resta per la firma della funzione sul server.
    'p_face': null,
    'p_club_password': clubPassword,
  };
}

abstract class RegistrationRepository {
  /// Salva i dati (funzione `complete_registration`); il ruolo arriva accettando il regolamento.
  Future<void> complete(RegistrationData data);

  /// Cambia la password del club con cui si entra nel Direttivo (solo Direttivo).
  Future<void> changeDirettivoPassword(String current, String next);
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
    final client = _ref.read(supabaseProvider);
    final params = data.toParams();
    Object? result;
    try {
      result = await client.rpc('complete_registration', params: params);
    } catch (e) {
      // Database non ancora aggiornato (senza la password del club): come prima.
      if (!isMissingFunction(e)) rethrow;
      result = await client.rpc(
        'complete_registration',
        params: {...params}..remove('p_club_password'),
      );
    }
    // Le password sbagliate non sono errori del database (così i tentativi restano
    // contati per il limite di 5 ogni 15 minuti): arrivano come risposta.
    switch (result) {
      case 'password_errata':
        throw const RegistrationError('Password del Direttivo non corretta');
      case 'password_club_errata':
        throw const SignupGateError(wrongClubPasswordText);
      case 'iscrizioni_chiuse':
        throw const SignupGateError(signupsClosedText);
    }
  }

  @override
  Future<void> changeDirettivoPassword(String current, String next) async {
    await _ref
        .read(supabaseProvider)
        .rpc(
          'set_direttivo_password',
          params: {'p_current': current, 'p_new': next},
        );
  }
}

class DemoRegistrationRepository implements RegistrationRepository {
  /// Password del Direttivo della sola demo: quella vera esiste solo come hash sul
  /// server e non va mai scritta nel codice.
  static const direttivoPassword = 'demo-direttivo';

  RegistrationData? last;
  String? newPassword;

  /// Password di iscrizione da chiedere (null = non serve, come nella demo).
  String? clubPassword;

  /// Come `complete_registration`: con una password sbagliata non si salva.
  @override
  Future<void> complete(RegistrationData data) async {
    if (clubPassword != null && data.clubPassword != clubPassword) {
      throw const SignupGateError(wrongClubPasswordText);
    }
    if (data.direttivo &&
        data.direttivoPassword != (newPassword ?? direttivoPassword)) {
      throw const RegistrationError('Password del Direttivo non corretta');
    }
    last = data;
  }

  @override
  Future<void> changeDirettivoPassword(String current, String next) async =>
      newPassword = next;
}

/// Errore della registrazione con il testo già pronto da mostrare.
class RegistrationError extends AppError {
  const RegistrationError(super.message);
}

/// Testo comprensibile per gli errori della registrazione (le regole del database
/// parlano già italiano: "Troppi tentativi con la password del Direttivo", ...).
String friendlyRegistrationError(Object e) =>
    friendlyError(e, action: 'Salvataggio non riuscito');

/// Password del Direttivo sbagliata, o troppi tentativi: si torna al passo 2 sul campo.
bool isDirettivoPasswordError(Object e) =>
    friendlyRegistrationError(e)
        .toLowerCase()
        .contains('password del direttivo');
