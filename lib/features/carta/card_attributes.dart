/// Le sei statistiche della carta, come le carte di FC in italiano: per i giocatori di
/// movimento VEL TIR PAS DRI DIF FIS, per i portieri TUF PRE RIN RIF VEL PIA (stesse
/// sei caselle, significato diverso).
const outfieldStatLabels = ['VEL', 'TIR', 'PAS', 'DRI', 'DIF', 'FIS'];
const goalkeeperStatLabels = ['TUF', 'PRE', 'RIN', 'RIF', 'VEL', 'PIA'];

const _outfieldNames = [
  'Velocità',
  'Tiro',
  'Passaggio',
  'Dribbling',
  'Difesa',
  'Fisico',
];
const _goalkeeperNames = [
  'Tuffo',
  'Presa',
  'Rinvio',
  'Riflessi',
  'Velocità',
  'Piazzamento',
];

bool isGoalkeeper(String? position) => position == 'POR';

/// Le sigle sulla carta per il ruolo [position].
List<String> cardStatLabels(String? position) =>
    isGoalkeeper(position) ? goalkeeperStatLabels : outfieldStatLabels;

/// I nomi per esteso (editor del Direttivo, lettore di schermo).
List<String> cardStatNames(String? position) =>
    isGoalkeeper(position) ? _goalkeeperNames : _outfieldNames;

/// Quanto conta ogni statistica per l'overall di un ruolo (i pesi sommano a 1): un
/// attaccante vale soprattutto per tiro e velocità, un difensore centrale per difesa e
/// fisico. È un suggerimento per il Direttivo, che decide l'overall.
const _weights = <String, List<double>>{
  'POR': [.22, .22, .08, .25, .03, .20],
  'DC': [.10, .02, .08, .05, .50, .25],
  'TD': [.25, .02, .15, .13, .30, .15],
  'TS': [.25, .02, .15, .13, .30, .15],
  'CDC': [.08, .05, .25, .12, .30, .20],
  'CC': [.10, .12, .32, .26, .10, .10],
  'COC': [.12, .22, .30, .30, .02, .04],
  'ED': [.25, .14, .22, .30, .04, .05],
  'ES': [.25, .14, .22, .30, .04, .05],
  'AD': [.28, .22, .15, .32, .01, .02],
  'AS': [.28, .22, .15, .32, .01, .02],
  'ATT': [.22, .40, .08, .20, .01, .09],
};

/// L'overall che corrisponde alle statistiche per il ruolo (senza ruolo: la media).
int? suggestedOverall(List<int>? stats, String? position) {
  if (stats == null || stats.length != 6) return null;
  final weights = _weights[position] ?? List.filled(6, 1 / 6);
  var total = 0.0;
  for (var i = 0; i < 6; i++) {
    total += weights[i] * stats[i];
  }
  return total.round().clamp(40, 99);
}

/// Le statistiche con il bonus della carta speciale (al massimo 99), come le carte
/// della settimana di FC che migliorano tutti i valori.
List<int>? statsWithBonus(List<int>? stats, int bonus) =>
    stats == null ? null : [for (final s in stats) (s + bonus).clamp(1, 99)];
