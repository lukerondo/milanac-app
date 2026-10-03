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

Al primo accesso l'utente è in stato **"in attesa"**: un membro del Direttivo lo approva e gli assegna
il ruolo. Così nessun estraneo vede i dati del club.

## 3. Ruoli e permessi

- **Direttivo** (= Esecutivo): crea/modifica rosa, formazione, calendario, risultati e media,
  albo d'oro, regolamento/storia, contatti social.
- **Giocatore**: legge tutto, gestisce **solo le proprie** presenze.
- **In attesa**: vede solo la schermata "account in approvazione".

I permessi sono applicati nel database con **Row Level Security** (non solo nell'interfaccia).

## 4. Sezioni dell'app

1. **Intro** – video MP4 (10–15s) incluso nell'app, barra di caricamento + stemma sovrapposti.
   Durante il video l'app carica sessione e dati. Tap per saltare.
2. **Home / Notizie** – card con: fonte, data, titolo, **breve descrizione** e bottone
   **"Leggi la notizia"** che apre il link originale. Filtri: *Tornei (FVPA/VPL)*, *Aggiornamenti FC 27*,
   *Ultimate Team*, *Pro Clubs*. Banner in evidenza quando esce un nuovo **Title Update**
   ("Aggiorna il gioco prima del match!") + notifica push.
3. **Menu laterale** (drawer):
   - Rosa completa · Formazione · Calendario · Risultati · Albo d'oro · Regolamento & Storia · Presenze
   - in fondo: icone social + sito web (modificabili dal Direttivo)
4. **Rosa completa** – foto, nome/gamertag, ruolo nel club (*Direttivo* / *Giocatore*),
   ruolo in campo, numero, data di ingresso.
5. **Formazione** – campo verde stile San Siro (disegnato in Flutter), scelta modulo
   (4-3-3, 4-2-3-1, 3-5-2…), 11 bollini: il Direttivo tocca un bollino e assegna il giocatore.
6. **Calendario** – vista mensile + lista; tipi evento: *Partita torneo*, *Amichevole*,
   *Allenamento*, *Riunione*, *Altro*. Solo il Direttivo crea eventi.
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
10. **Presenze** – per ogni serata (default **21:30**) il giocatore segna:
    *Presente* · *Presente ma arrivo alle __:__* · *Assente* (+ nota).
    Lista del giorno con lo stato di tutti; accanto a ogni giocatore lo **storico**
    (ultime presenze, % presenze, ritardi). Promemoria push il giorno della partita.

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
```

Storage buckets: `avatars`, `trophies`, `match-media` (tutti privati, letti tramite URL firmati).

## 6. Notizie – raccolta automatica

Script (Dart o Python) eseguito da **GitHub Actions ogni 3 ore**:
1. legge le fonti (RSS dove esiste, altrimenti pagina HTML o JSON pubblico);
2. estrae **titolo, data, link, immagine e una descrizione breve** (max ~300 caratteri, mai l'articolo intero);
3. classifica per categoria con parole chiave; scarta duplicati (`url` unico);
4. salva in `news` e, se è un Title Update, invia la notifica push;
5. cancella le notizie più vecchie di 60 giorni.

L'esecuzione regolare tiene anche **attivo** il progetto Supabase Free (che va in pausa dopo 7 giorni di inattività).

### Fonti iniziali (modificabili da tabella `news_sources`)
| Categoria | Fonte |
|---|---|
| Tornei | FVPA – fvpa.net (sito + X @FVPA_net) |
| Tornei | Virtual Pro League Italy – virtualproleague.com (X @VPLItaly) |
| Aggiornamenti | EA SPORTS FC 27 – ea.com/it/games/ea-sports-fc/fc-27/news |
| Aggiornamenti | Patchbot – patchbot.io/games/ea-sports-fc-27 |
| Aggiornamenti / UT | Everyeye.it – sezione EA Sports FC |
| Ultimate Team | FifaUltimateTeam.it |
| Pro Clubs / community | Reddit r/EASportsFC e r/FIFAProClubs (feed `.rss`) |

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
    features/  intro/ news/ rosa/ formazione/ calendario/ risultati/
               albo_doro/ regolamento/ presenze/ settings/
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
