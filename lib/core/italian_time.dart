/// Ora italiana (Europe/Rome), calcolata senza pacchetti.
///
/// Il server ragiona in ora italiana (scadenza delle risposte alle 18:30, "oggi",
/// allenamento delle 21:30): l'app fa lo stesso qualunque sia il fuso del telefono
/// (giocatore all'estero, fuso impostato male).
///
/// Regole dell'Unione europea: ora legale (UTC+2) dall'ultima domenica di marzo
/// all'ultima domenica di ottobre, con il cambio alle 01:00 UTC; il resto dell'anno UTC+1.
library;

/// Scarto da UTC dell'ora italiana nell'istante [instant].
Duration italianOffset(DateTime instant) {
  final utc = instant.toUtc();
  final summerStart = DateTime.utc(utc.year, 3, _lastSunday(utc.year, 3), 1);
  final summerEnd = DateTime.utc(utc.year, 10, _lastSunday(utc.year, 10), 1);
  final summer = !utc.isBefore(summerStart) && utc.isBefore(summerEnd);
  return Duration(hours: summer ? 2 : 1);
}

/// Giorno del mese dell'ultima domenica di [month].
int _lastSunday(int year, int month) {
  final last = DateTime.utc(year, month + 1, 0); // ultimo giorno del mese
  return last.day - last.weekday % DateTime.sunday;
}

/// L'orologio italiano nell'istante [instant]: anno, mese, giorno, ore e minuti come
/// li segna un orologio in Italia. È un'ora "da parete" (in UTC solo come contenitore,
/// così i salti dell'ora legale del telefono non la toccano): si confronta e si formatta
/// solo insieme ad altre ore italiane, mai con `toLocal()`.
DateTime italianClock(DateTime instant) {
  final utc = instant.toUtc();
  return utc.add(italianOffset(utc));
}

/// L'istante (in UTC) in cui l'orologio italiano segna [clock]: contano anno, mese, giorno,
/// ore e minuti di [clock], non il suo fuso. L'ora che a fine marzo non esiste (02:00-02:59)
/// vale come quella dopo il cambio; di quella doppia di fine ottobre vale la prima.
DateTime fromItalianClock(DateTime clock) {
  final fields = DateTime.utc(
    clock.year,
    clock.month,
    clock.day,
    clock.hour,
    clock.minute,
    clock.second,
    clock.millisecond,
    clock.microsecond,
  );
  final summer = fields.subtract(const Duration(hours: 2));
  if (italianOffset(summer) == const Duration(hours: 2)) return summer;
  return fields.subtract(const Duration(hours: 1));
}

/// Il giorno in Italia nell'istante [instant], a mezzanotte come i giorni delle presenze.
DateTime italianDay(DateTime instant) {
  final clock = italianClock(instant);
  return DateTime(clock.year, clock.month, clock.day);
}
