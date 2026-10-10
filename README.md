# MILANAC Pro Club – App

App ufficiale del **MILANAC Pro Club** (EA SPORTS FC 27 – Pro Clubs) per **Android** e **iOS**,
scritta in **Flutter** con backend **Supabase** (piano gratuito).

- Architettura e roadmap: [`docs/ARCHITETTURA.md`](docs/ARCHITETTURA.md)
- Prompt per video intro, albo d'oro e stemma: [`docs/PROMPT_GRAFICA.md`](docs/PROMPT_GRAFICA.md)
- Schema database + permessi: [`supabase/migrations/`](supabase/migrations)

## Stato

| Fase | Contenuto | Stato |
|---|---|---|
| 1 | Scheletro, tema rossonero, Intro, Login social, approvazione utenti, menu laterale, Home notizie | ✅ |
| 2 | Rosa (con approvazione accessi), Regolamento & Storia, contatti social modificabili | ✅ |
| 3 | Presenze con storico (notifiche push nella fase 8) | ✅ |
| 4 | Calendario, Risultati + media (link / foto / clip 15s) | ✅ |
| 5 | Formazione (campo San Siro, 7 moduli, panchina) | ✅ |
| 6 | Notizie automatiche ogni 3 ore (GitHub Actions + Supabase) | ✅ |
| 7 | Albo d'oro: sala trofei 2.5D, scelta stagione, trofei del Direttivo | ✅ |
| 8 | Icona, avvio, notifiche push, privacy, eliminazione account, build firmate | ✅ (configurazione account: `docs/PUBBLICAZIONE.md`) |
| A | Riquadro "Stasera" in Home, formazione pubblicata con notifica personale | ✅ |
| – | Squadre MILANAC e MILANAC FUTURO (assegnate dal Direttivo, una o entrambe) | ✅ |
| B | Carta FUT del giocatore (overall, stile, statistiche del club, condivisione) | ✅ |
| C | Tattiche & Build (video dei creator per ruolo, schemi del Direttivo) | ✅ |
| D | Chat a canali (Main, Presenze automatiche, Fantacalcio, Tattiche) | ✅ |
| E | Tornei (link, classifica facoltativa, partite collegate) | ✅ |
| – | Colonna sonora: musica di sottofondo scelta dal telefono, con muto | ✅ |
| – | Sala Direttivo, Impostazioni (dati e foto della carta), Home "Notizie dal mondo FC" con pannello Stasera | ✅ |
| F | Voti dopo la partita, carta "Uomo partita", Squadra della settimana | ✅ |
| G | Traguardi sbloccabili (badge su profilo e carta) e walkout stile FUT | ✅ |
| – | Restyling: font sportivo, sfondo stadio, card a vetro, transizioni, vibrazioni | ✅ |
| **Nuova app · 1** | Brand della vecchia app (colori, Oswald, stemma), accesso con email e password, registrazione in tre passi (dati, squadra e ruolo con password del Direttivo, volto disegnato), regolamento su pergamena con versioni e accettazione obbligatoria, Impostazioni con volto e account. Via voti, Uomo partita e Top 11. | ✅ |
| **Nuova app · 2** | Home con i riquadri Mondo Proclub (video dei creator proposti dai giocatori e pubblicati dal Direttivo; notizie con avvisi di aggiornamento FC 27 e console) e Presenze (serata di oggi, risposta entro le 18:30). Presenze a calendario con promemoria alle 18:00 e assenze automatiche alle 18:30 (pg_cron), eventi con notifica, canali Generale / Milan AC / Milan AC Futuro / Tattiche / Comunicazioni / Direttivo, Sala Direttivo con correzioni dopo la scadenza, formazione annunciata in Comunicazioni e PDF con le mini carte. | ✅ |
| **Nuova app · 3** | Chat in stile Telegram (risposte citate, vocali fino a 2 minuti, foto e vocali che scadono dopo 60 giorni, link cliccabili, "Nuovi messaggi"), carte speciali al posto dei voti (nero/oro della settimana assegnata dal Direttivo per reparto con bonus +1…+5, blu elettrico automatica per tripletta o tre partite senza subire gol, annuncio in Comunicazioni, walkout e traguardi dedicati), Rosa con mini carte, ricerca e filtri, Tornei con foto o logo. | ✅ |
| **Nuova app · 4** | Lavagna tattica in Tattiche e schemi: gettoni dei giocatori delle due squadre (dalla formazione), pennello heatmap, frecce continue o tratteggiate, annulla, schemi salvati con immagine esportata; registrazione del replay (voce e mosse sincronizzate, fino a 5 minuti) con anteprima e invio in chat, dove si riproduce nell'app e sparisce dopo 3 giorni. | ✅ |
| Nuova app · 5 | Stanza vocale (Agora) e rifiniture | ⏳ |

## Provare l'app subito (modalità demo)

Senza configurare nulla l'app parte in **modalità demo**: niente login, dati di esempio.

```bash
flutter pub get
flutter run            # telefono/emulatore collegato
flutter run -d chrome  # nel browser
```

## Video intro

Metti il video in `assets/video/intro.mp4` (verticale 1080×1920, 10–15s, max ~8 MB).
Se il file non c'è, l'intro usa l'immagine `assets/images/intro_bg.png`.

## Collegare Supabase (gratis)

1. Crea un progetto su [supabase.com](https://supabase.com) (piano Free, regione Europa).
2. Crea le tabelle: secret `SUPABASE_DB_URL` + workflow **Database** (vedi `docs/SETUP_SUPABASE.md`),
   oppure SQL Editor con i file di `supabase/migrations/` in ordine.
3. **Authentication → URL Configuration** → aggiungi agli *Redirect URLs*:
   `com.milanacproclub.milanac://login-callback`
4. **Authentication → Providers**:
   - **Google** – client OAuth da Google Cloud Console
   - **Azure** (Microsoft/Hotmail/Outlook) – app registrata su Azure con tenant `common`
     (account personali Microsoft abilitati)
   - **Apple** – obbligatorio su iOS (Services ID dal tuo account Apple Developer)
   - **Yahoo** – provider *Custom OIDC* con identificativo `yahoo`, issuer
     `https://api.login.yahoo.com`, client creato su developer.yahoo.com
5. Avvia l'app collegata al progetto (URL e chiave *publishable* sono in `env/prod.json`;
   la chiave publishable è pubblica per design, la sicurezza è data dalle policy RLS):
   ```bash
   flutter run --dart-define-from-file=env/prod.json
   ```
   **Non** inserire mai nel repository la chiave `secret` / `service_role`.
6. Fai il primo login, poi nell'SQL Editor nomina il primo Direttivo:
   ```sql
   update profiles set club_role = 'direttivo' where display_name = 'Il tuo nome';
   ```
   Da lì in poi è il Direttivo ad approvare gli altri dall'app.

## Notizie automatiche

Il workflow **Notizie** (`.github/workflows/news.yml`) gira ogni 3 ore: legge le fonti in
`tools/news_fetcher/sources.json`, filtra le notizie pertinenti, salva titolo, breve descrizione
e link nella tabella `news` e cancella quelle più vecchie di 60 giorni.

- Serve il secret **`SUPABASE_SECRET_KEY`** nel repository (vedi `docs/SETUP_SUPABASE.md`).
- Prova manuale: Actions → *Notizie* → *Run workflow* (spunta "Prova senza salvare" per un test).
- Aggiungere/togliere fonti: modifica `sources.json` (RSS o Atom; le fonti che non rispondono vengono saltate).

## Build

- **CI**: ad ogni push GitHub Actions esegue `flutter analyze`, `flutter test` e la prova delle
  migrazioni su un PostgreSQL vuoto con i controlli di sicurezza (`tools/db/test/run.sh`).
- **Database**: il workflow *Database* applica le nuove migrazioni solo se quella prova passa.
- **Funzioni**: il workflow *Funzioni* pubblica la funzione Supabase `notify` (notifiche personali).
- **APK**: Actions → *CI* → *Run workflow* → scarica l'artifact `milanac-apk` (usa `env/prod.json`).
- **Rilascio Android (.aab firmato)**: Actions → *Rilascio Android*.
- **iOS**: Codemagic (`codemagic.yaml`) → TestFlight.
- Guida completa per gli store: [`docs/PUBBLICAZIONE.md`](docs/PUBBLICAZIONE.md).

Identificativo app: `com.milanacproclub.milanac`
