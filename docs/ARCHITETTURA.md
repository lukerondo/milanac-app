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
- `sensors_plus` – effetto parallasse 2.5D dell'Albo d'oro
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

1. **Chi sei**: nome, cognome, anno di nascita (li vede solo il Direttivo), **nome sulla carta**
   (è il nome mostrato in tutta l'app: `display_name`), motto.
2. **Squadra e ruolo**: Milan AC o Milan AC Futuro (entrambe solo per il Direttivo); "Faccio parte
   del Direttivo" richiede la **password del club** (solo l'hash bcrypt sta in `app_config`,
   si cambia dall'app con `set_direttivo_password`) e almeno un'etichetta tra Capitano,
   Reclutatore, Organizzatore, Gestore; ruolo in campo, numero, piattaforma.
3. **Il tuo volto**: avatar disegnato dall'app (parametri in `profiles.face`), usato in rosa, chat,
   carta e walkout.

Il profilo resta `pending` finché non si **accetta il regolamento** (`accept_rules`): da lì il ruolo
richiesto diventa effettivo. Non serve nessuna approvazione del Direttivo; il Direttivo può
comunque sospendere un membro (`active = false`).

## 3. Ruoli e permessi

- **Direttivo**: crea/modifica rosa, formazione, calendario, risultati e media, albo d'oro,
  regolamento (bozza + pubblicazione) e storia, contatti social; assegna l'**overall** delle carte.
- **Giocatore**: legge tutto, gestisce **solo le proprie** presenze, i propri dati e il proprio
  volto, la propria carta (ruolo, numero, stile, piattaforma, non l'overall), scrive in chat e
  aggiunge link. Non può cambiarsi ruolo, squadra, stato, overall o data d'ingresso (trigger).
- **Squadre**: Milan AC e Milan AC Futuro; i giocatori stanno in una sola squadra, chi è del
  Direttivo può stare in entrambe.
- **Registrazione in corso** (`pending`): vede solo i passi della registrazione e il regolamento.
- **Sospeso** (`active = false`): vede solo la pagina "account non attivo".

I permessi sono applicati nel database con **Row Level Security** (non solo nell'interfaccia).

### Regolamento con versioni

Gli articoli vivono in una **bozza** (`rules_articles`, solo Direttivo). "Pubblica" crea una riga in
`rules_versions` con la fotografia degli articoli e manda la notifica `rules`. Ogni profilo
ricorda la versione accettata (`rules_accepted_version`): se non è l'ultima, l'app mostra la
pergamena e lascia accettare solo dopo essere arrivati in fondo e dopo 2 minuti (non mostrati).

## 4. Sezioni dell'app

1. **Intro** – video MP4 (10–15s) incluso nell'app, barra di caricamento + stemma sovrapposti.
   Durante il video l'app carica sessione e dati. Tap per saltare.
2. **Home** – due riquadri. **Mondo Proclub**: ultimo video dei creator, avviso di
   aggiornamento FC 27 e della propria console, scorciatoie a video e notizie.
   **Presenze**: la serata di oggi della propria squadra (allenamento delle 21:30 o l'evento
   del Direttivo), risposta con i tre pulsanti fino alle 18:30, conteggi.
3. **Menu laterale** (drawer), a gruppi, con stemma, nome del club, nome e cognome e ruolo:
   - *Squadra*: Presenze · Formazione · Calendario · Risultati · Chat
   - *Club*: Mondo Proclub · Rosa completa · La mia carta · Carte speciali · Tornei ·
     Albo d'oro · Regolamento & Storia · Tattiche & Build · Colonna sonora
   - *Direttivo*: Sala Direttivo (solo per chi ne fa parte)
   - in fondo: icone social + sito web (modificabili dal Direttivo)
3b. **Mondo Proclub** – scheda *Video*: i video dei creator pubblicati dal Direttivo,
   filtrabili per ruolo; i giocatori ne propongono (notifica al Direttivo, che pubblica o
   scarta; notifica a chi ha proposto). Scheda *Notizie*: card con fonte, data, titolo,
   descrizione breve e "Leggi la notizia"; filtri *Aggiornamenti FC 27*, *Console*, *Tornei*,
   *Pro Clubs*, *Ultimate Team*; avviso in evidenza per un nuovo Title Update o un
   aggiornamento della console.
4. **Rosa completa** – vista predefinita a **mini carte** (volto, overall con l'eventuale
   bonus della carta speciale, ruolo, nome), oppure carte grandi o elenco (foto, gamertag,
   ruolo nel club, ruolo in campo, numero, data di ingresso). Ricerca per nome, cognome o
   gamertag; filtri per squadra, reparto (POR/DIF/CEN/ATT) e *Solo Direttivo*. Un tocco apre
   la carta del giocatore.
5. **Formazione** – campo verde stile San Siro (disegnato in Flutter), scelta modulo
   (4-3-3, 4-2-3-1, 3-5-2…), 11 bollini: il Direttivo tocca un bollino e assegna il giocatore.
6. **Calendario** – vista mensile + lista; tipi evento: *Partita torneo*, *Amichevole*,
   *Allenamento*, *Riunione*, *Altro*. Solo il Direttivo crea eventi (notifica alla squadra
   o a tutti). Ogni giorno compare l'allenamento automatico delle 21:30 per la squadra che
   non ha altro in programma.
7. **Risultati** – partite (torneo/amichevole, avversario, punteggio, marcatori).
   Per ogni partita il Direttivo allega media in **due modi**:
   - **Link** (YouTube, Twitch, Instagram, TikTok…) → riprodotto/aperto nell'app
   - **Clip caricata**: video **max 15 secondi** (tagliato nell'app) o foto, compressi prima dell'upload
8. **Albo d'oro** – scena 2.5D: illustrazione della sala trofei con un giocatore del Pro Club
   (di spalle) che ammira la bacheca; le mensole sono "vive": i trofei caricati dal Direttivo
   (PNG trasparente) vengono posizionati sulle mensole, con riflessi, luce e leggero parallasse
   inclinando il telefono. **Selettore stagione in alto a destra** (es. 2025/26, 2026/27).
   Tocco su un trofeo → dettaglio (competizione, data, finale, foto).
   Evoluzione futura: trofei 3D ruotabili (`.glb`).
9. **Regolamento & Storia** – una pagina con due schede, testo formattato modificabile dal Direttivo.
10. **Presenze** – a calendario: oggi cerchiato in rosso, un puntino per ogni evento. Per il
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
    **PDF con le mini carte** (campo, volto, nome, ruolo, overall, panchina).
13. **Carta FUT** – "La mia carta" e carte in Rosa: overall deciso dal Direttivo (livelli bronzo,
    argento, oro, rossonera 85+), statistiche dal club (presenze, puntualità, serate, gol dai
    marcatori, mesi nel club, % vittorie), condivisione come immagine. Se il giocatore ha una
    carta speciale in corso, la carta mostrata è quella (colori nero/oro o blu elettrico,
    overall con il bonus) ovunque: carta, Rosa, mini carte del PDF, anello sul volto in chat.
14. **Tattiche & Build** – schemi del club con immagine e spiegazione (Direttivo); i video dei
    creator stanno in Mondo Proclub (la lavagna arriva con la fase 4).
15. **Chat** – canali Generale, Milan AC, Milan AC Futuro (visibili a chi ci gioca),
    Tattiche & Schemi, Comunicazioni (scrive solo il Direttivo: avvisi, formazioni, carte
    speciali), Sala Direttivo (riservato). In stile Telegram: bolle rosse per i propri
    messaggi e grigie per gli altri (volto e nome), separatori per giorno, "Nuovi messaggi"
    dall'ultima lettura, risposta citata, menu a pressione lunga (rispondi, copia, elimina con
    conferma), **vocali** (tieni premuto il microfono, scorri a sinistra per annullare, max
    2 minuti, lettore con avanzamento), foto, link cliccabili, pulsante "torna in fondo".
    Foto e vocali scadono dopo 60 giorni: il messaggio resta con "Allegato scaduto" (pulizia
    notturna). Non letti, canali silenziabili, notifiche.
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
20. **Walkout** – animazione stile pacchetti FUT (luci, bandiera, ruolo, stemma, giro della
    carta) alla prima apertura dopo l'approvazione, quando l'overall sale e quando arriva una
    carta speciale (con i suoi colori); rivedibile dalla carta.
21. **Sala Direttivo** – contatori (senza risposta stasera, formazioni da pubblicare, video
    proposti) e azioni: presenze di stasera (correzioni anche dopo le 18:30), formazioni,
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
profiles      + first_name, last_name, birth_year, motto, direttivo_roles[], face(jsonb),
                registration_completed_at, rules_accepted_version, rules_accepted_at
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
`match_number` numera le giornate (partite ufficiali con risultato dal 1° agosto). Chat:
`messages_before_insert` (risposta nello stesso canale, scadenza a 60 giorni),
`expire_attachments()` ogni notte alle 3:15 (pg_cron) toglie gli allegati scaduti, mette i
file in `storage_cleanup` e chiama la funzione `notify` (evento `cleanup`) che li elimina
dallo Storage con la chiave di servizio; i messaggi eliminati accodano i loro file allo
stesso modo.

Lavori automatici con **pg_cron**: `attendance_tick()` gira ogni minuto e, in ora italiana,
alle 18:00 manda il promemoria a chi non ha risposto e alle 18:30 segna le assenze automatiche
(una volta sola al giorno, grazie a `daily_jobs`). Le risposte dei giocatori sono bloccate dopo
le 18:30 dalle policy (`attendance_open`); il Direttivo corregge sempre. Nei test l'ora si fissa
con l'impostazione `milanac.now` (`app_now()`).

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

## 8. Struttura del codice

```
milanac-app/
  lib/
    main.dart
    core/      theme/ (rossonero), router/, supabase/, auth/, widgets/
    features/  intro/ auth/ registrazione/ home/ mondo/ news/ rosa/ carta/ carte/ formazione/
               calendario/ risultati/ presenze/ chat/ tornei/ albo_doro/ regolamento/
               tattiche/ musica/ traguardi/ walkout/ volto/ direttivo/ impostazioni/
  assets/      video/intro.mp4, images/ (stemma, sala trofei), fonts/
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
speciali, rosa con mini carte, tornei · 4 lavagna tattica con replay · 5 stanza vocale (Agora).
