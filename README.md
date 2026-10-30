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
| **Nuova app · 5** | Stanza vocale in ogni chat (Agora): cuffie nella barra, *Entra* / *Apri la stanza* con un tocco, microfono e vivavoce, cerchio verde su chi parla, avviso "stanza aperta" a chi è nel canale, chiusura automatica quando esce l'ultimo; minuti del mese nella Sala Direttivo (10.000 gratis). Rifiniture: errori con "Riprova", larghezza massima su tablet. | ✅ |
| **Nuova app · 6** | Review completa e correzioni (sicurezza del database, dati in tempo reale ovunque, "Riprova" e nuovi tentativi quando manca la rete, ora italiana, stanza vocale robusta e attiva anche a schermo spento, chat con paginazione ed eliminazioni per tutti), nuovo design **nero oro** (scuro, chiaro o automatico come il telefono) con Barlow e Oswald, **barra in basso a cinque schede** (Home, Presenze, Partite, Chat, Club) al posto del menu laterale, profilo e impostazioni dalla foto in alto, preferenze delle notifiche, ricerca nei messaggi, nome e cognome visibili solo al Direttivo, avviso dei nuovi ingressi nella Sala Direttivo, APK sotto gli 80 MB. | ✅ |
| **Nuova app · 7** | Poteri del Direttivo: promozioni e retrocessioni con le etichette (tracciate nella Sala Direttivo), eliminazione dell'account di un membro con doppia conferma, iscritti in attesa visibili, foto del profilo da togliere, stanza vocale chiusa per tutti; il club non resta mai senza Direttivo. | ✅ |
| **Nuova app · 8** | Stile Pro Clubs, una novità alla volta: carte vive (riflesso che passa, inclinazione col dito, brillii delle speciali), apertura del pacchetto (bustina da aprire con un tocco o tirandola su, luce dello strappo del colore della carta, San Siro che si accende, fuochi d'artificio, overall che sale punto per punto, vibrazioni a tempo), partita come una diretta TV (tabellone, minuti dei gol, cronaca con il punteggio dopo ogni gol, foto e clip in grande e a tutto schermo; migrazione 0027), animazioni e vibrazioni (la mini carta della Rosa vola fino alla carta grande, caricamenti d'oro al posto delle rotelline, vibrazioni su gol, presenze e conferme, spegnibili da Impostazioni → Aspetto), archetipi e PlayStyle (13 archetipi come in Pro Clubs con icona e descrizione, 30 PlayStyle di cui 2 PlayStyle+ in oro sulla carta; migrazione 0028), formazione in prospettiva (campo inclinato come il menu tattiche di FC, con le mini carte in piedi al posto dei pallini), Match Day in Home (nel giorno della partita la card della serata ha il tabellone con il conto alla rovescia, chi è pronto, la formazione e il codice del party da copiare; migrazione 0029), grafica del risultato da condividere (poster nero oro 4:5 con San Siro, punteggio nel tabellone, marcatori con i minuti e carte della giornata, con anteprima; o il testo), sondaggi in chat (domanda e da 2 a 10 risposte, una o più scelte, barre con le percentuali dopo il voto, voti in tempo reale, chi ha votato, chiusura da chi l'ha creato o dal Direttivo; migrazione 0030), promemoria partita (un'ora prima e dieci minuti prima, con il codice del party, esclusi gli assenti e spegnibili da Impostazioni; il Direttivo chiama la squadra in lobby dal Match Day; migrazione 0031). | ✅ |
| **Nuova app · 9** | Carte FUT fedeli con la foto vera: carta come gli oggetti di FUT (scudo con le tacche, finiture bronzo/argento/oro con i raggi, rossonera 85+, nero/oro e blu elettrico per le speciali), la foto caricata dal giocatore dalla galleria e inquadrata da lui (sposta e allarga) sfumata dentro la carta, sagoma grigia senza foto, sei statistiche FUT in riga scritte dal giocatore o dal Direttivo (VEL TIR PAS DRI DIF FIS, per i portieri TUF PRE RIN RIF VEL PIA; il bonus delle speciali sale anche su quelle; migrazione 0032), mini carte della Rosa nello stesso stile. Via il volto disegnato ovunque: registrazione, Impostazioni, chat, rosa e PDF usano la foto; copia delle foto sul telefono (niente download a ogni avvio). | ✅ |

## Provare l'app subito (modalità demo)

Senza configurare nulla l'app parte in **modalità demo**: niente login, dati di esempio.

```bash
flutter pub get
flutter run            # telefono/emulatore collegato
flutter run -d chrome  # nel browser
```

## Video intro

`assets/video/intro.mp4` è il **walkout della squadra** (20 s, verticale 720×1280, circa 3 MB,
con l'audio: nell'intro si sente, e il pulsante accanto a "Salta" lo spegne e se lo ricorda):
sei striscioni dipinti a mano in
curva (FORZA IMMU!, FABIO UNICO CAPITANO, CHRYS IL MOTORE, MARTIN UNO DI NOI, ZIO FOR
PRESIDENT, VICIO NUMBER ONE), ognuno seguito dal suo giocatore che esce dagli spogliatoi, poi
l'azione che parte da Immu, il gol di Fabio, l'esultanza sotto la curva e il fumo che sfuma nel
nero; sotto, i cori della curva e lo speaker ("Ha segnato il Milan AC!"). Il video l'ha generato
Seedance 2.5 su Leonardo con i prompt di `docs/PROMPT_GRAFICA.md`; gli striscioni erano vuoti.
Le scritte sugli striscioni, la U di IMMU sulla maglia del portiere (l'AI aveva scritto IMMI: la u
è la prima n della scritta capovolta, fotogramma per fotogramma, così carattere e luce sono quelli
del video; gli altri nomi sono quelli generati) e il montaggio sono degli script in
`tools/video/walkout/` (OpenCV + ffmpeg: `striscioni.py`, `nomi.py`, `monta.py`, lanciati da
una cartella con il video in `in/` e i fotogrammi degli shot in `shots/`). La versione per i
social (1080×1920) non sta nel repository. Se il video manca, l'intro resta su sfondo nero.

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
6. Registrati dall'app scegliendo *Faccio parte del Direttivo* con la password del Direttivo
   (impostata nel database: vedi `docs/SETUP_SUPABASE.md`, § 8): il primo del Direttivo che entra
   scrive e pubblica il regolamento d'ingresso.
   Gli altri entrano da soli, completando la registrazione e accettando il regolamento: non c'è
   un'approvazione, ma il Direttivo riceve l'avviso di ogni nuovo ingresso nella chat *Sala
   Direttivo* e può togliere dalla Rosa chi non conosce (Sala Direttivo → Rosa e squadre).
7. **Stanza vocale** (facoltativa): serve un account Agora gratuito; App ID e App Certificate vanno
   nei secret `AGORA_APP_ID` e `AGORA_APP_CERTIFICATE` di GitHub (vedi `docs/SETUP_SUPABASE.md`, § 13).
   Senza, l'app funziona lo stesso e la stanza dice che la voce non è ancora attiva.

## Notizie automatiche

Il workflow **Notizie** (`.github/workflows/news.yml`) gira ogni 3 ore: legge le fonti in
`tools/news_fetcher/sources.json`, filtra le notizie pertinenti, salva titolo, breve descrizione
e link nella tabella `news` e cancella quelle più vecchie di 60 giorni.

- Serve il secret **`SUPABASE_SECRET_KEY`** nel repository (vedi `docs/SETUP_SUPABASE.md`).
- Prova manuale: Actions → *Notizie* → *Run workflow* (spunta "Prova senza salvare" per un test).
- Aggiungere/togliere fonti: modifica `sources.json` (RSS o Atom; le fonti che non rispondono vengono saltate).

## App per Mac

Versione di prova per Mac (macOS 12 o successivo), ricompilata a ogni modifica di `main`:
scarica `MILANAC.dmg` dalla release
[App per Mac](https://github.com/lukerondo/milanac-app/releases/tag/mac-di-prova).

1. Apri `MILANAC.dmg` e trascina **MILANAC** nella cartella **Applicazioni**.
2. La prima volta: tasto destro (o ctrl-clic) su MILANAC in Applicazioni → **Apri** → **Apri**.
   Il Mac chiede conferma perché l'app non è firmata con un account sviluppatore Apple.
3. Su macOS 15 o successivo, se il Mac la blocca senza il pulsante *Apri*: **Impostazioni di
   Sistema → Privacy e sicurezza** → in fondo alla pagina **Apri comunque**.

Le notifiche push sul Mac per ora non ci sono; le clip highlights si caricano dal telefono.

## Build

- **CI**: ad ogni push GitHub Actions esegue `flutter analyze`, `flutter test` e la prova delle
  migrazioni su un PostgreSQL vuoto con i controlli di sicurezza (`tools/db/test/run.sh`).
- **Database**: il workflow *Database* applica le nuove migrazioni solo se quella prova passa.
- **Funzioni**: il workflow *Funzioni* pubblica la funzione Supabase `notify` (notifiche personali).
- **APK**: Actions → *CI* → *Run workflow* → scarica l'artifact `milanac-apk` (usa `env/prod.json`).
  `MILANAC-arm64.apk` (circa 70 MB) è quello da installare sui telefoni; `MILANAC.apk` contiene
  anche i processori a 32 bit. Le estensioni video di Agora restano fuori dal pacchetto.
- **Rilascio Android (.aab firmato)**: Actions → *Rilascio Android*.
- **iOS**: Codemagic (`codemagic.yaml`) → TestFlight.
- **Mac**: workflow *Mac* (`.github/workflows/mac.yml`) → `MILANAC.dmg` firmato ad-hoc, come
  artifact `milanac-mac` e (da `main` o a mano) nella release *App per Mac*.
- Guida completa per gli store: [`docs/PUBBLICAZIONE.md`](docs/PUBBLICAZIONE.md).

Identificativo app: `com.milanacproclub.milanac`
