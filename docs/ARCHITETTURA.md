# MILANAC Pro Club – Architettura dell'app

App ufficiale del **MILANAC Pro Club** (EA SPORTS FC 27 – Pro Clubs).
Obiettivi: **zero costi di gestione**, durata nel tempo, pubblicazione su **Google Play** e **App Store**
con un unico codice.

## 1. Stack

| Livello | Tecnologia | Costo |
|---|---|---|
| App Android + iOS (+ sito web) | **Flutter** (Dart) | 0 € |
| Database, login, file, permessi | **Supabase** (piano Free) | 0 € |
| Raccolta notizie | **GitHub Actions** (job programmato ogni 3h) | 0 € |
| Notifiche push | **Firebase Cloud Messaging** (solo FCM) | 0 € |
| Sito web | Flutter Web su **GitHub Pages** | 0 € |
| Build iOS | **Codemagic** free / GitHub Actions macOS | 0 € |
| Account store | Google Play + Apple Developer | già pagati |

### Pacchetti Flutter principali
- `supabase_flutter` – database, auth, storage, realtime
- `flutter_riverpod` – gestione stato · `go_router` – navigazione
- `video_player` – intro e clip highlights · `youtube_player_iframe` – video da link
- `image_picker`, `video_compress`, `video_trimmer` – caricamento media (taglio a 15s)
- `table_calendar` – calendario · `url_launcher` – apertura notizie/social
- `firebase_messaging` – notifiche push

## 2. Login (Supabase Auth)

| Provider | Come | Note |
|---|---|---|
| Google | provider nativo Supabase | |
| Microsoft (Hotmail/Outlook/Live) | provider nativo "Azure" (tenant `common`) | |
| Yahoo | **provider OIDC personalizzato** (`https://api.login.yahoo.com`) | supportato da Supabase come custom OIDC |
| **Apple** | provider nativo Supabase | **obbligatorio su iOS** (regola App Store 4.8: se offri login social devi offrire anche "Accedi con Apple") |

| **Email e password** | Supabase Auth (email confermata con link; password dimenticata via email) | serve un servizio SMTP (vedi `docs/SETUP_SUPABASE.md`) |

### Registrazione (nuova app)

Dopo il primo accesso l'utente completa tre passi, salvati dalla funzione `complete_registration`:

1. **Chi sei**: nome, cognome, anno di nascita (li vedono solo l'interessato e il Direttivo:
   stanno nella tabella riservata `profile_private`), **nome sulla carta**
   (è il nome mostrato in tutta l'app: `display_name`), motto.
2. **Squadra e ruolo**: Milan AC o Milan AC Futuro (entrambe solo per il Direttivo); "Faccio parte
   del Direttivo" richiede la **password del club** (solo l'hash bcrypt sta in `app_config`,
   si cambia dall'app con `set_direttivo_password`) e almeno un'etichetta tra Capitano,
   Reclutatore, Organizzatore, Gestore; ruolo in campo, numero, piattaforma.
3. **La tua foto** (facoltativa, si può caricare dopo): una foto vera dalla galleria, inquadrata
   nel riquadro 4:5 della carta (sposta e allarga con due dita), salvata come JPEG 720×900 in
   `avatars/<id>/foto_<ms>.jpg` (`profiles.avatar_path`) e caricata subito, prima della fine
   della registrazione. È l'unica immagine del membro nell'app: carta, rosa, chat, walkout e
   PDF; senza foto la **sagoma grigia** come in FUT. Il volto disegnato non c'è più (la
   colonna `face` e il parametro `p_face`, sempre null, restano per le app vecchie).

Il profilo resta `pending` finché non si **accetta il regolamento** (`accept_rules`): da lì il ruolo
richiesto diventa effettivo. Non serve nessuna approvazione del Direttivo: ogni nuovo ingresso
compare però nella Sala Direttivo (messaggio con nome, ruolo e squadra, che arriva anche come
notifica) e il Direttivo può togliere dalla Rosa chi non conosce (`active = false`).

## 3. Ruoli e permessi

- **Direttivo**: crea/modifica rosa, formazione, calendario, risultati e media, albo d'oro,
  regolamento (bozza + pubblicazione) e storia, contatti social; assegna l'**overall** delle carte.
  Tutti i membri del Direttivo hanno gli stessi poteri, anche gli uni sugli altri (migrazione
  `0026`), dalla scheda del membro (Sala Direttivo → Rosa e squadre, o "Dati del membro" sulla
  sua carta):
  - **promuove** un giocatore nel Direttivo con le etichette (Capitano, Reclutatore,
    Organizzatore, Gestore) o lo **retrocede** (le etichette si azzerano); promozioni e
    retrocessioni compaiono nella Sala Direttivo con chi le ha decise;
  - **elimina definitivamente l'account** di un altro membro (`delete_member_account`, doppia
    conferma), anche di chi si è registrato ma non è mai entrato ("In attesa di entrare");
  - **toglie la foto del profilo** di un membro e **chiude una stanza vocale** per tutti
    (`close_voice_room`);
  - elimina i messaggi di chiunque, corregge le presenze di tutti, pubblica o toglie i video.

  Il club non resta mai senza Direttivo: il database rifiuta la retrocessione, la rimozione o
  l'eliminazione dell'account dell'ultimo membro attivo (trigger `direttivo_guard` e controllo
  in `delete_my_account`).
- **Giocatore**: legge tutto, gestisce **solo le proprie** presenze, i propri dati e il proprio
  foto, la propria carta (ruolo, numero, stile, statistiche FUT, piattaforma, non l'overall),
  scrive in chat e
  aggiunge link. Non può cambiarsi ruolo, squadra, stato, overall o data d'ingresso (trigger).
- **Squadre**: Milan AC e Milan AC Futuro; i giocatori stanno in una sola squadra, chi è del
  Direttivo può stare in entrambe.
- **Registrazione in corso** (`pending`): vede solo i passi della registrazione e il regolamento.
- **Sospeso** (`active = false`): vede solo la pagina "account non attivo".

I permessi sono applicati nel database con **Row Level Security** (non solo nell'interfaccia).

### Regolamento con versioni

Gli articoli vivono in una **bozza** (`rules_articles`, solo Direttivo). "Pubblica" crea una riga in
`rules_versions` con la fotografia degli articoli e manda la notifica `rules`. Ogni profilo
ricorda la versione accettata (`rules_accepted_version`): se non è l'ultima, l'app mostra il
regolamento e lascia accettare solo dopo essere arrivati in fondo e dopo 2 minuti (non mostrati).
Finché non esiste **nessuna versione pubblicata** nessuno resta bloccato: chi ha completato la
registrazione entra con `enter_club()` (prende il ruolo richiesto, senza versione accettata); il
primo del Direttivo che entra trova l'editor del regolamento d'ingresso con la spiegazione
(`/regolamento/scrivi`; "Più tardi" lo rimanda e lascia il promemoria nella Sala Direttivo).
Chi pubblica una versione risulta averla già accettata; tutti gli altri la leggono e la
accettano al primo accesso successivo.

## 4. Sezioni dell'app

1. **Intro** – video MP4 incluso nell'app ("Lampi di leggende", 15 s: otto leggende del Milan,
   da Maldini a Ibrahimović, con nome in oro e lampi bianchi, fatto con
   `tools/video/intro_leggende.py`), barra di
   caricamento + stemma sovrapposti, "Salta" in alto.
   Durante il video l'app carica sessione e dati. Tap per saltare.
2. **Home** – due riquadri. **Mondo Proclub**: ultimo video dei creator, avviso di
   aggiornamento FC 27 e della propria console, scorciatoie a video e notizie.
   **Presenze**: la serata di oggi della propria squadra (allenamento delle 21:30 o l'evento
   del Direttivo), risposta con i tre pulsanti fino alle 18:30, conteggi. Nel giorno di una
   partita diventa il **Match Day**: tabellone con lo stemma contro l'avversario e il conto
   alla rovescia al calcio d'inizio (poi "in corso" e il fischio finale), chi è pronto con i
   volti, lo stato della formazione e il codice del party da copiare (lo scrive il
   Direttivo), quando arrivano i **promemoria** (un'ora prima e dieci minuti prima, o
   "spenti" con il link alle impostazioni) e, per il Direttivo, *Chiama* la squadra in
   lobby; la partita di stasera non si ripete in "Prossima partita".
3. **Barra in basso a cinque schede** (sempre visibile, ognuna ricorda dove eri rimasto):
   - *Home* · *Presenze* · *Partite* (Calendario, Risultati, Tornei; da qui Formazione e
     dettaglio partita) · *Chat* (con i non letti sull'icona) · *Club* (Rosa, Carte speciali,
     Tattiche, Mondo Proclub, Albo d'oro, Regolamento e Storia, Colonna sonora, Tornei, Sala
     Direttivo per chi ne fa parte, contatti social modificabili dal Direttivo)
   - in alto a destra la propria foto: profilo con la carta, i traguardi e le Impostazioni
     (dati, foto, notifiche, aspetto scuro/chiaro/automatico come il telefono, vibrazioni,
     account);
   - animazioni: dalla Rosa la mini carta vola fino alla carta grande; i caricamenti sono
     d'oro (arco che gira con il pallone, barra che scorre); vibrazioni su tocchi, gol e
     vittorie, risposte alle presenze e conferme, tutte da `core/haptics.dart` e spegnibili;
   - i vecchi indirizzi delle notifiche (/calendario, /risultati, /tornei, /carta) portano
     alla nuova posizione; una sottosezione aperta da notifica torna indietro alla sua scheda.
3b. **Mondo Proclub** – scheda *Video*: i video dei creator pubblicati dal Direttivo,
   filtrabili per ruolo; i giocatori ne propongono (notifica al Direttivo, che pubblica o
   scarta; notifica a chi ha proposto). Scheda *Notizie*: card con fonte, data, titolo,
   descrizione breve e "Leggi la notizia"; filtri *Aggiornamenti FC 27*, *Console*, *Tornei*,
   *Pro Clubs*, *Ultimate Team*; avviso in evidenza per un nuovo Title Update o un
   aggiornamento della console.
4. **Rosa completa** – vista predefinita a **mini carte** FUT (foto o sagoma, overall con
   l'eventuale bonus della carta speciale, ruolo, nome), oppure elenco (foto, gamertag,
   ruolo nel club, ruolo in campo, numero, data di ingresso). Ricerca per nome, cognome o
   gamertag; filtri per squadra, reparto (POR/DIF/CEN/ATT) e *Solo Direttivo*. Un tocco apre
   la carta del giocatore.
5. **Formazione** – campo in prospettiva come il menu tattiche di FC (disegnato in Flutter:
   erba a strisce, linee proiettate, la porta avversaria lontana), scelta modulo (4-3-3,
   4-2-3-1, 3-5-2…), 11 mini carte in piedi (overall, ruolo, foto, colori della carta
   speciale), più piccole in fondo: il Direttivo tocca una carta e assegna il giocatore.
6. **Calendario** – vista mensile + lista; tipi evento: *Partita torneo*, *Amichevole*,
   *Allenamento*, *Riunione*, *Altro*. Solo il Direttivo crea eventi (notifica alla squadra
   o a tutti). Ogni giorno compare l'allenamento automatico delle 21:30 per la squadra che
   non ha altro in programma.
7. **Risultati** – partite (torneo/amichevole, avversario, punteggio, marcatori e, se il
   Direttivo li scrive, i minuti dei gol). La pagina della partita è come una diretta TV:
   tabellone con le caselle del punteggio e i marcatori con i minuti sotto ogni squadra,
   cronaca dal calcio d'inizio al fischio finale (linea del tempo, gol con il volto del
   marcatore e il punteggio dopo ogni gol), foto, clip e video di YouTube in grande da
   scorrere, che si aprono a tutto schermo una dopo l'altra. Dal tasto di condivisione si
   apre l'anteprima della **grafica del risultato** (poster 1080×1350 nero oro con San Siro,
   punteggio nel tabellone, marcatori con i minuti, esito, carte della giornata e nota) da
   condividere come immagine, oppure il risultato come testo.
   Per ogni partita il Direttivo allega media in **due modi**:
   - **Link** (YouTube, Twitch, Instagram, TikTok…) → riprodotto/aperto nell'app
   - **Clip caricata**: video **max 15 secondi** (tagliato nell'app) o foto, compressi prima dell'upload
8. **Albo d'oro** – stagioni a schede (es. 2025/26, 2026/27), targa con il numero di trofei ed
   elenco dei trofei caricati dal Direttivo (foto o sagoma disegnata); tocco su un trofeo →
   dettaglio (competizione, data, finale, foto).
9. **Regolamento & Storia** – una pagina con due schede, testo formattato modificabile dal Direttivo.
10. **Presenze** – settimana a colpo d'occhio (e mese intero): oggi in oro, un puntino per ogni evento. Per il
    giorno scelto: la serata della squadra, la propria risposta (*Presente* · *In ritardo*
    con orario e nota obbligatoria · *Assente* con nota facoltativa), totali e gli elenchi
    (senza risposta, presenti, in ritardo, assenti). Le risposte chiudono alle **18:30**
    (anche per i giorni successivi si risponde in anticipo); alle 18:00 promemoria a chi
    non ha risposto; alle 18:30 chi non ha risposto diventa "assente, non ha risposto"
    (in grigio, conta come assenza). Dopo, solo il Direttivo corregge, e resta registrato.
    Scheda *Statistiche*: percentuale, puntuali, ritardi e assenze per giocatore.

11. **Riquadro Presenze in Home** – la serata di oggi con la risposta rapida (vedi Home).
12. **Formazione pubblicata** – una formazione per squadra; resta in bozza finché il Direttivo non
    la pubblica, poi ogni giocatore della squadra riceve la notifica personale (titolare con
    ruolo o panchina), l'annuncio compare in *Comunicazioni* e chiunque può scaricare il
    **PDF con le mini carte** (campo, foto, nome, ruolo, overall, panchina).
13. **Carta FUT** – "La mia carta" e carte in Rosa disegnate come gli oggetti di FUT (FC 24–26):
    scudo con le tacche in alto, overall e ruolo a sinistra con i PlayStyle+, la **foto caricata
    dal giocatore** sfumata dentro la carta (senza foto la sagoma grigia; sulla propria carta
    l'invito "Carica la tua foto"), nome, le **sei statistiche FUT** in riga (VEL TIR PAS DRI
    DIF FIS; per i portieri TUF PRE RIN RIF VEL PIA) scritte dal giocatore o dal Direttivo
    (`profiles.fut_stats`, migrazione 0032), bandiera e stemma. Finiture metalliche per
    livello (bronzo, argento, oro con i raggi; rossonera 85+ a righe strette; grigia senza
    overall), condivisione come immagine. Le statistiche del club (presenze, puntualità,
    serate, gol, mesi nel club, % vittorie) stanno sotto la carta. Se il giocatore ha una
    carta speciale in corso, la carta mostrata è quella (nero/oro come la TOTW, blu elettrico
    a schegge; il bonus sale su overall e statistiche) ovunque: carta, Rosa, mini carte del
    PDF, anello sulla foto in chat.
    Archetipo (uno dei 13 come in Pro Clubs, con icona e descrizione, o uno stile scritto a
    mano) e PlayStyle (fino a 6, di cui 2 PlayStyle+ nei rombi d'oro sulla carta), scelti dal
    giocatore o dal Direttivo e mostrati sotto la carta.
14. **Tattiche & Build** – schemi del club con immagine e spiegazione (Direttivo) e la
    **lavagna tattica**: campo con i gettoni dei giocatori (dalla formazione della squadra,
    con numero e nome sulla carta; anche avversari e gettoni vuoti), pennello *Fuoco* (la
    heatmap gialla e rossa si accumula dove si insiste), *Freccia* (trascina; doppio tocco
    per le tratteggiate), *Annulla*, *Pulisci*, nuova lavagna da un modulo. *Salva* mette lo
    schema (gettoni, frecce, heatmap in `tactics.board`) in Tattiche e schemi con l'immagine
    esportata; tutti lo guardano, il Direttivo lo modifica. *Registra* chiede il microfono e
    salva la voce e ogni azione con il suo istante (fino a 5 minuti); allo stop l'anteprima
    con il replay sincronizzato, poi "Invia in chat" (canale a scelta, predefinito Tattiche e
    Schemi) oppure elimina. I video dei creator stanno in Mondo Proclub.
15. **Chat** – canali Generale, Milan AC, Milan AC Futuro (visibili a chi ci gioca),
    Tattiche & Schemi, Comunicazioni (scrive solo il Direttivo: avvisi, formazioni, carte
    speciali), Sala Direttivo (riservato). In stile Telegram: bolle rosse per i propri
    messaggi e grigie per gli altri (volto e nome), separatori per giorno, "Nuovi messaggi"
    dall'ultima lettura, risposta citata, menu a pressione lunga (rispondi, copia, elimina con
    conferma), **vocali** (tieni premuto il microfono, scorri a sinistra per annullare, max
    2 minuti, lettore con avanzamento), foto, link cliccabili, pulsante "torna in fondo".
    Foto e vocali scadono dopo 60 giorni: il messaggio resta con "Allegato scaduto" (pulizia
    notturna). **Sondaggi** (icona accanto alla foto): domanda e da 2 a 10 risposte, una o
    più scelte; si vota toccando una risposta, le barre d'oro con le percentuali compaiono
    dopo il voto (o a sondaggio chiuso), "N voti" apre chi ha votato, "Ritira il voto";
    chi l'ha creato o il Direttivo lo chiude dal menu a pressione lunga. Il **replay della lavagna** arriva come riquadro con il campo e il pulsante
    Play: si riproduce nell'app (audio più mosse, pochi KB, non è un video) e scade dopo 3
    giorni. Non letti, canali silenziabili, notifiche. **Stanza vocale** (Agora): le cuffie
    nella barra di ogni canale aprono la stanza a schermo intero (sempre scura): chi c'è
    (volto, bordo e alone d'oro su chi parla, microfono barrato su chi è in muto, "In
    ascolto"), *Entra* o *Apri la stanza*, microfono, vivavoce, *Esci*; la freccia giù la
    riduce a una striscia. Chi apre la stanza avvisa i membri del canale (la notifica apre la
    chat con la stanza già aperta); sotto la barra la card "Stanza vocale aperta · canale —
    Marco e Luca sono dentro — Entra" e, durante la chiamata, la striscia con cronometro,
    microfono ed esci sempre a portata di dito (un tocco riapre la stanza; si può cambiare
    pagina senza uscire). La stanza si chiude quando esce l'ultimo o dopo 3 minuti
    senza segni di vita dell'app. Sul web la stanza non è disponibile.
16. **Tornei** – foto o logo (caricati dal Direttivo), link al sito, squadra, stato,
    classifica facoltativa compilata dal Direttivo, partite collegate.
17. **Colonna sonora** – ognuno sceglie un file audio dal proprio telefono (es. compilation
    FIFA): suona in loop, muto sempre in alto. Nessuna canzone è inclusa nell'app (diritti);
    playlist e video ufficiali su YouTube/Spotify condivisi come link.
18. **Carte speciali** – al posto dei voti. Dal dettaglio di una partita con risultato il
    Direttivo sceglie un premiato per reparto (POR, DIF, CEN, ATT) per la **carta nero/oro
    della settimana**, con bonus da +1 a +5 sull'overall; la **blu elettrico** (+5) arriva da
    sola quando si salva il risultato: tripletta (dai marcatori) o portiere alla terza partita
    ufficiale di fila senza subire gol (il portiere della partita viene dalla formazione
    pubblicata, correggibile nell'editor). Durano 7 giorni; la blu batte la nero/oro.
    Ogni assegnazione aggiorna l'annuncio in *Comunicazioni* ("Carte speciali della Nª
    giornata…"), avvisa la squadra e manda al premiato la notifica che apre la sua carta
    con il walkout dedicato. La sezione *Carte speciali* mostra la settimana in corso e lo
    storico per giornata.
19. **Traguardi** – 11 badge (bronzo, argento, oro, leggenda): presenze, gol, un mese senza
    ritardi, un anno nel club, overall 85+, carta della settimana, blu elettrico.
20. **Walkout** – apertura del pacchetto come in FUT: la bustina nero oro si apre con un
    tocco (o tirandola in su) e dallo strappo esce la luce del colore della carta; poi lampo,
    San Siro che si accende, fuochi d'artificio (carte speciali e dall'oro in su), bandiera,
    ruolo, stemma, giro della carta e overall che sale punto per punto (o il bonus della
    speciale che si somma), con vibrazioni a tempo; a carta ferma la carta è viva. Parte alla
    prima apertura dopo l'approvazione, quando l'overall sale e quando arriva una carta
    speciale (con i suoi colori); rivedibile dalla carta.
21. **Sala Direttivo** – contatori (senza risposta stasera, formazioni da pubblicare, video
    proposti, minuti voce del mese su 10.000) e azioni: presenze di stasera (correzioni anche dopo le 18:30), formazioni,
    nuovo evento, avviso a tutti (in Comunicazioni), nuovo risultato, rosa e squadre,
    Mondo Proclub, chat del Direttivo, contatti social.

## 5. Modello dati (Supabase / PostgreSQL)

```
profiles      id(uuid=auth.uid), display_name, gamertag, avatar_url, club_role(direttivo|giocatore|pending),
              field_position, shirt_number, joined_at, active
formations    id, name, module, is_current, updated_by, updated_at
formation_slots formation_id, slot_index(0-10), x, y, label, player_id
events        id, type, title, description, starts_at, ends_at, location, created_by
matches       id, event_id?, competition, kind(torneo|amichevole), opponent, home_away,
              goals_for, goals_against, played_at, notes
match_media   id, match_id, type(link|video|photo), url_or_path, duration_s(<=15), caption, uploaded_by
seasons       id, label('2025/26'), starts_on, ends_on
trophies      id, season_id, name, competition, won_on, image_path, shape, shelf, position, description
pages         slug(regolamento|storia), content(markdown), updated_by, updated_at
attendance    id, player_id, date, status(presente|ritardo|assente), arrival_time(default 21:30), note
              UNIQUE(player_id, date)
news          id, source, category, title, summary(<=300 car.), url UNIQUE, image_url, published_at
club_links    id, kind(instagram|whatsapp|tiktok|youtube|twitch|sito), url, order
-- dalla migrazione 0006 in poi
profiles      + teams(text[] milanac|futuro), overall(40-99), play_style, platform(ps5|xbox|pc)
formations    + team, published_at, published_by
events        + team (null = tutto il club)      matches + team, tournament_id
device_tokens token, user_id, platform            app_config  key, value (solo server)
shared_links  id, category(musica|build), title, url, note, tag(ruolo), created_by
tactics       id, title, module, description, image_path
channels      id, slug, name, description, icon   messages  id, channel_id, author_id, kind(user|system),
              body, image_path, meta              channel_mutes / channel_reads (per utente)
tournaments   id, name, organizer, url, team, status, starts_on, ends_on, notes
tournament_standings  tournament_id, team_name, won, drawn, lost, goals_for, goals_against, is_us
rules_articles id, sort_order, title, body                -- bozza del Direttivo
rules_versions number, snapshot(jsonb), published_at       -- versioni pubblicate del regolamento
profiles      + motto, direttivo_roles[], face(jsonb, non più usato), fut_stats(jsonb, 0032),
                registration_completed_at, rules_accepted_version, rules_accepted_at
                (nome, cognome e anno di nascita: dalla 0025 in profile_private)
app_config    + direttivo_password_hash (bcrypt)
-- dalla migrazione 0017
attendance    + auto (assenza automatica), set_by (chi ha corretto); nota obbligatoria per il ritardo
daily_jobs    day, job, done_at                    -- promemoria e assenze fatti una volta al giorno
channels      + team (milanac|futuro), direttivo_writes   -- Generale, Milan AC, Futuro, Tattiche, Comunicazioni, Direttivo
shared_links  category(musica|video) + status(proposto|pubblicato), published_by, published_at
news          + platform (ps5|xbox) per la categoria console
-- dalla migrazione 0018
messages      + reply_to (stesso canale), audio_path, duration_s(<=120), expires_at, expired_at
              (foto e vocali scadono dopo 60 giorni: resta "Allegato scaduto")
storage_cleanup bucket, path, queued_at              -- file da togliere dallo Storage (solo server)
matches       + goalkeeper_id (dalla formazione pubblicata al primo risultato)
special_cards id, player_id, kind(nero_oro|blu), reparto(POR|DIF|CEN|ATT), bonus(1-5), reason,
              match_id, team, starts_at, ends_at(+7 giorni), assigned_by
              (per partita: una carta per giocatore e tipo, una nero/oro per reparto)
tournaments   + image_path (foto o logo nel bucket tournaments)
-- dalla migrazione 0019
tactics       + board (jsonb: modulo, squadra, gettoni, frecce, heatmap), team
messages      + replay_path (JSON delle azioni con i tempi; l'audio in audio_path fino a 300 s);
              un replay scade dopo 3 giorni
-- dalla migrazione 0024
profiles      + notify_prefs (jsonb: presenze|chat|notizie = false per spegnerle)
-- dalla migrazione 0025
profile_private id(→ profiles), first_name, last_name, birth_year, birth_date, updated_at
              (RLS: solo l'interessato e il Direttivo leggono e scrivono)
-- dalla migrazione 0027
matches       + timeline (jsonb: [{minute 1-130, side us|them, scorer?}], mai più gol del
              risultato; l'app salva senza se il server non è ancora aggiornato)
-- dalla migrazione 0028
profiles      + play_styles (text[]: codici dei PlayStyle, "+" in fondo per i PlayStyle+;
              al massimo 6, di cui 2 "+"). L'archetipo resta play_style (testo libero, con
              i 13 archetipi proposti nell'app)
-- dalla migrazione 0029
events        + party_code (text, 1-40 caratteri: il codice del party della partita, lo
              scrive il Direttivo e si copia dal Match Day in Home)
-- dalla migrazione 0031
event_reminders id, event_id(→ events), kind (ora | lobby | chiamata), starts_at, sent_at,
              sent_by; i due automatici una volta sola per partita e orario (se la partita
              si sposta ripartono); nessuna policy (solo il server)
-- dalla migrazione 0030
messages      un sondaggio è un messaggio con meta {type: poll, options [2-10, 1-80
              caratteri, diverse], multiple, closed_at?} e la domanda nel testo (max 300)
poll_votes    message_id(→ messages), user_id(→ profiles), options smallint[] (vuoto =
              ritirato), voted_at; una riga per chi vota, aggiornata se cambia idea (il tempo
              reale filtrato riceve le modifiche, non le eliminazioni). RLS: la legge chi
              vede il canale; si scrive solo con vote_poll
```

Funzioni e trigger: `notify_push` (chiama la funzione Edge `notify` tramite pg_net),
pubblicazione formazione → notifica + annuncio in *Comunicazioni*, nuovo messaggio → notifica,
nuovo evento → notifica, `chat_overview()` (non letti + ultimo messaggio per canale),
risultato inserito → notifica alla squadra, `complete_registration()` / `accept_rules()` /
`publish_rules()` / `set_direttivo_password()` (registrazione e regolamento), `player_stats()`
(numeri per i traguardi, comprese le carte speciali ricevute), video proposto / pubblicato →
notifica, notizia su aggiornamenti o console → notifica (al massimo una ogni 12 ore per tipo).
Carte speciali: `assign_special_cards(partita, premi)` (solo Direttivo: una nero/oro per
reparto, sostituisce l'elenco precedente, aggiorna l'annuncio in *Comunicazioni* con
`announce_special_cards` e manda gli avvisi `special_card` / `special_cards_week`);
`award_blue_cards` gira dal trigger del risultato e legge i marcatori con `scorer_goals`
(nome sulla carta, cognome o gamertag, "Rossi (3)" / "x3") e la serie del portiere;
`match_number` numera le giornate (partite ufficiali con risultato dal 1° agosto). Eliminare
una partita toglie le sue carte e il loro annuncio e ricontrolla la serie del portiere delle
due partite ufficiali successive; la blu ha sempre la precedenza sulla nero/oro della stessa
partita; correggere un bonus o un reparto non manda nuovi avvisi. La formazione pubblicata
prende l'ora del server e il portiere del risultato viene dalla formazione pubblicata.
`save_standings` e `save_club_links` (solo Direttivo) salvano classifica e contatti in una
transazione. Nuovo ingresso (`pending` → giocatore/Direttivo) → messaggio nella Sala Direttivo
(`on_member_joined`). Chat:
`messages_before_insert` (risposta nello stesso canale, scadenza a 60 giorni),
`expire_attachments()` ogni notte alle 3:15 (pg_cron) toglie gli allegati scaduti (foto e
vocali dopo 60 giorni, replay della lavagna dopo 3), mette i file in `storage_cleanup` e
chiama la funzione `notify` (evento `cleanup`) che li elimina dallo Storage con la chiave di
servizio; i messaggi eliminati accodano i loro file allo stesso modo. Il replay è un file
JSON con la lavagna di partenza e le azioni con l'istante (`lib/features/lavagna/`): la
stessa macchina a stati disegna la lavagna e rifà le mosse in riproduzione. Sondaggi:
`vote_poll(messaggio, opzioni)` (sostituisce le scelte di prima; niente voti a sondaggio
chiuso, fuori elenco o doppi dove se ne sceglie una) e `close_poll(messaggio)` (chi l'ha
creato o il Direttivo; scrive `closed_at` nel meta e lo restituisce); il vincolo
`messages_poll_valid` controlla domanda e opzioni. Prima della migrazione l'app non crea
sondaggi e lo dice.

Lavori automatici con **pg_cron**: `attendance_tick()` gira ogni minuto e, in ora italiana,
alle 18:00 manda il promemoria a chi non ha risposto e alle 18:30 segna le assenze automatiche
(una volta sola al giorno, grazie a `daily_jobs`). Le risposte dei giocatori sono bloccate dopo
le 18:30 dalle policy (`attendance_open`); il Direttivo corregge sempre. Nei test l'ora si fissa
con l'impostazione `milanac.now` (`app_now()`). Promemoria partita (migrazione `0031`):
`match_reminders_tick()` gira ogni minuto e per le partite (torneo e amichevole) manda
"Tra un'ora si gioca" (solo se la partita era già in calendario e mancano più di 15 minuti) e
"Tutti in lobby" dieci minuti prima, con il codice del party, alla squadra esclusi gli assenti
(categoria "Promemoria partita", spegnibile); `call_to_lobby(evento)` è la chiamata del
Direttivo (da due ore prima a due ore dopo l'inizio, una ogni 3 minuti, arriva sempre).

Stanza vocale (migrazione `0020`): `voice_rooms` (una aperta per canale, `opened_by`,
`closed_at`) e `voice_sessions` (ingressi con `agora_uid`, `heartbeat_at`, `muted`, `left_at`),
lette in tempo reale dall'app e scritte solo dalle funzioni `open_voice_room` (crea o riusa la
stanza, avvisa i membri del canale con l'evento `voice_room`), `join_voice_room`,
`voice_heartbeat` (ogni minuto dall'app), `leave_voice_room` (chiude la stanza se è vuota) e
`voice_minutes(mese)` (minuti-partecipante, per la Sala Direttivo). `voice_tick()` gira ogni
minuto con pg_cron (`stanze-vocali`): segna uscito chi non dà segni di vita da 3 minuti e chiude
le stanze rimaste vuote. L'audio non passa da Supabase: va su Agora (`agora_rtc_engine`, profilo
comunicazione, solo audio); il biglietto d'ingresso lo firma la funzione Edge `voice-token`
(token di un'ora, rinnovato dall'app senza uscire; App Certificate solo nei segreti) solo per
chi ha una sessione aperta nella stanza. Il numero utente Agora è ricavato dall'id del profilo
(`agoraUidFor`, stesso calcolo in `agora_uid_for` sul server) e il biglietto vale solo per quel
numero, così si sa subito chi parla e nessuno entra con il nome di un altro. Una stanza per
volta (entrando in un'altra si esce dalla prima); finiti i 10.000 minuti gratuiti del mese non
si entra più fino al primo del mese. Con l'app in background o lo schermo spento la stanza resta
attiva: su Android con un servizio in primo piano di tipo microfono (notifica fissa "Sei nella
stanza vocale"), su iOS con la modalità audio in background.

Storage buckets: `avatars`, `trophies`, `match-media`, `tactics`, `chat` (foto e vocali),
`tournaments` (tutti privati, letti tramite URL firmati, con limiti di dimensione e tipo di
file).

Ogni migrazione è provata in CI su un PostgreSQL vuoto (`tools/db/test/`: parti di Supabase
simulate + controlli su RLS e trigger) prima di essere applicata al database vero.

## 6. Notizie – raccolta automatica

Script (Dart o Python) eseguito da **GitHub Actions ogni 3 ore**:
1. legge le fonti (RSS dove esiste, altrimenti pagina HTML o JSON pubblico);
2. estrae **titolo, data, link, immagine e una descrizione breve** (max ~300 caratteri, mai l'articolo intero);
3. classifica per categoria con parole chiave; scarta duplicati (`url` unico);
4. salva in `news`; un trigger manda l'avviso push per gli aggiornamenti di FC 27 (a tutti) e
   delle console (a chi ha quella piattaforma nel profilo), al massimo uno ogni 12 ore per tipo;
5. cancella le notizie più vecchie di 60 giorni.

L'esecuzione regolare tiene anche **attivo** il progetto Supabase Free (che va in pausa dopo 7 giorni di inattività).

### Fonti iniziali (modificabili in `tools/news_fetcher/sources.json`)
| Categoria | Fonte |
|---|---|
| Tornei | FVPA – feed del sito fvpa.net |
| Tornei | Google News: "FVPA" / "Virtual Pro League" |
| Aggiornamenti | Google News IT + EN: "FC 27" + title update / aggiornamento / patch |
| Ultimate Team | Google News: "FC 27" + "Ultimate Team" · FifaUltimateTeam.it (feed) |
| Pro Clubs | Google News: "FC 27" + Pro Clubs / The Grounds · Reddit r/FIFAProClubs (top del giorno) |
| Console | Google News: PS5 / Xbox + aggiornamento di sistema, firmware (categoria `console`, con piattaforma) |

Google News raccoglie anche EA SPORTS, Everyeye, FUTBIN e le altre testate: per queste mostriamo
la testata e il link, la descrizione rimanda all'articolo originale.

## 7. Limiti del piano gratuito e come li gestiamo

| Limite Supabase Free | Impatto | Soluzione |
|---|---|---|
| 500 MB database | testo: anni di dati | pulizia notizie vecchie |
| 1 GB file | clip 15s a 720p ≈ 3–5 MB → ~200 clip | compressione in app, foto max 1600px, archiviazione clip vecchie |
| 5 GB traffico/mese | ~1.000 visualizzazioni clip/mese | cache locale dei video, preferire i link per video lunghi |
| pausa dopo 7 gg inattivi | app ferma | job notizie ogni 3h la tiene attiva |
| Agora Free: 10.000 minuti-partecipante/mese | 4 persone per un'ora = 240 minuti | contatore nella Sala Direttivo, stanze chiuse da sole quando vuote |
| Peso dell'APK (Agora porta circa 75 MB di librerie native per architettura) | APK arm64 ≈ 70 MB, universale ≈ 180 MB | le estensioni facoltative di Agora (video, lip sync, effetti) restano fuori (`packaging.jniLibs.excludes`), l'APK universale non include x86, sul Play Store l'app bundle manda solo la parte del telefono |

## 8. Struttura del codice

```
milanac-app/
  lib/
    main.dart
    core/      theme (nero oro, scuro e chiaro), router (5 schede e porte), auth/, push/,
               errors, audio_focus, appearance, italian_time
    features/  intro/ auth/ registrazione/ home/ mondo/ news/ rosa/ carta/ carte/ formazione/
               calendario/ risultati/ presenze/ chat/ tornei/ albo_doro/ regolamento/
               tattiche/ lavagna/ voce/ musica/ traguardi/ walkout/ foto/ direttivo/
               impostazioni/ profilo/ club/ partite/
  assets/      video/intro.mp4 (720p), images/ (stemma), fonts/ (Oswald, Barlow)
  supabase/    migrations/ (schema + RLS), seed.sql
  tools/news_fetcher/   script raccolta notizie
  .github/workflows/    news.yml, build-android.yml, build-ios.yml, web-pages.yml
```

## 9. Roadmap

1. Scheletro progetto, tema, Intro, Login, approvazione utenti, menu laterale
2. Rosa, Regolamento & Storia, contatti social
3. Presenze (con storico) + notifiche
4. Calendario, Risultati + media (link / clip 15s)
5. Formazione (campo San Siro)
6. Notizie (job automatico)
7. Albo d'oro 2.5D
8. Icone, store listing, privacy policy, pubblicazione Play Store / App Store
9. Stasera e formazione pubblicata · squadre MILANAC/FUTURO · carta FUT · Tattiche & Build ·
   chat a canali · tornei · colonna sonora

Nuova app (ottobre 2026, vedi README): 1 fondamenta e ingresso · 2 Home, Mondo Proclub,
presenze a calendario, Sala Direttivo, PDF della formazione · 3 chat stile Telegram, carte
speciali, rosa con mini carte, tornei · 4 lavagna tattica con replay · 5 stanza vocale (Agora)
e rifiniture.
