# Il sito del club (sito/)

Il sito di MILANAC Pro Club è una sola pagina statica: `sito/index.html` con dentro stile e
script, più le cartelle `img/`, `video/` e `audio/`. La pagina non ha niente da compilare. Le
animazioni (GSAP) e i caratteri (Google Fonts) arrivano da CDN gratuite.

Sotto lo stesso indirizzo, in `/app/`, c'è la **web app**: la stessa app del telefono, nel
browser (vedi più sotto).

## Pubblicazione su Vercel (gratis)

Il sito è il progetto **milanacproclub** su Vercel (account del club, piano Hobby), online su
<https://milanacproclub.vercel.app>. Vercel prende i file direttamente dal repository GitHub
(ramo `main`, cartella `sito`): non c'è niente da caricare a mano.

- **Ripubblicare dopo una modifica**: dopo aver unito la modifica in `main`, chiedi a Claude di
  ripubblicare il sito (lo fa con il connettore Vercel) oppure, su Vercel, apri il progetto →
  *Deployments* → *Create Deployment* dal ramo `main`.
- **Pubblicazione automatica** a ogni aggiornamento di `main` (consigliata, una volta sola): su
  Vercel, progetto → *Settings* → *Git* → *Connect Git Repository* → `lukerondo/milanac-app`.
  La Root Directory è già `sito` (con *Include files outside the root directory* attivo: la
  web app si compila dal resto del repository). Da quel momento ogni modifica unita in `main`
  va online da sola.
- Il collegamento tra Vercel e il profilo GitHub (Settings → Authentication) deve restare attivo:
  è quello che permette a Vercel di leggere il repository.

Un dominio proprio, quando ci sarà, si aggiunge su Vercel in *Settings → Domains* del progetto;
poi si aggiorna l'indirizzo nei tag `og:url`, `og:image` e `canonical` di `sito/index.html` e
in `WEB_APP_URLS` di `tools/db/auth_urls.py` (indirizzi della web app per l'accesso).

## La web app (`/app/`)

<https://milanacproclub.vercel.app/app/> è l'app MILANAC nel browser, per chi non può o non vuole
usarla dal telefono (per esempio dal PC, mentre gioca). Stessi account, stessi dati: chi è già
nel club accede con la sua email e la sua password.

- **Come si pubblica**: a ogni pubblicazione del sito Vercel lancia
  `tools/web/build_vercel.sh` (è il `buildCommand` di `sito/vercel.json`), che scarica Flutter,
  compila l'app per il web e la mette in `sito/app/`. Ci mette qualche minuto. Se la
  compilazione fallisce la pubblicazione si ferma e online resta la versione di prima.
- **Niente secret**: l'indirizzo di Supabase e la chiave pubblica sono in `env/prod.json`.
- **Chi può registrarsi**: solo chi ha la *password di iscrizione* che dà il Direttivo
  (vedi `docs/SETUP_SUPABASE.md`, "Password di iscrizione"). Vale anche per l'app sul telefono.
- **Accesso e link delle email**: gli indirizzi della web app devono stare tra i *Redirect URLs*
  di Supabase. Li aggiunge da solo il workflow **Database** (`tools/db/auth_urls.py`).
- **Stanza vocale**: dal browser si entra nella stessa stanza dei telefoni (SDK Web di Agora,
  `web/stanza_vocale.js`). Il browser chiede il permesso del microfono; l'audio esce da dove
  dice il computer. L'SDK non sta nel repository: lo scarica `tools/web/agora_sdk.sh` quando
  si compila (versione fissa, impronta controllata).
- **Chat**: messaggi vocali e replay della lavagna si registrano anche dal browser. Dove il
  browser sa registrare in AAC (Chrome ed Edge su Windows e Mac, Safari) il formato è quello
  dell'app; altrimenti (Firefox, Linux) è WAV, che si ascolta ovunque ma pesa di più. Con la
  tastiera del computer **Invio** manda il messaggio e **Maiusc+Invio** va a capo.
- **Sul computer**: da 1000 punti di larghezza la web app si dispone come un'app da PC
  (`lib/shared/wide_layout.dart`): menu laterale al posto della barra in basso, chat a due
  colonne (elenco dei canali e conversazione fianco a fianco), rosa con cinque carte per riga
  e pagine a schermo intero con i comandi al centro. Sotto quella larghezza (telefoni,
  finestre strette) resta tutto com'è.
- **Notifiche**: le stesse dei telefoni, anche con la pagina chiusa (Web Push, senza
  Firebase). La prima volta l'app lo propone; poi si accendono e spengono da Impostazioni →
  Notifiche → *Notifiche in questo browser*. Con l'app aperta e davanti l'avviso esce in
  basso nella pagina, altrimenti è una notifica del sistema e il clic porta alla sezione.
  Il messaggio lo riceve `web/notifiche-sw.js`, un service worker con un ambito suo
  (`/app/notifiche/`); `web/notifiche.js` chiede il permesso e iscrive il browser. Su
  **iPhone e iPad** funzionano solo dall'app aggiunta alla schermata Home (Condividi →
  *Aggiungi alla schermata Home*). Su computer arrivano finché il browser è in esecuzione.
  Le chiavi le genera il workflow **Funzioni** (vedi `docs/SETUP_SUPABASE.md`, "Notifiche
  nel browser").
- **Cosa non c'è nel browser** (resta nell'app sul telefono): la musica scelta dal proprio
  dispositivo.
- **Aggiornarla**: dopo ogni modifica all'app unita in `main` va ripubblicato il sito, come
  sopra. La web app non si aggiorna da sola finché Vercel non è collegato al repository.

Per provarla in locale: `tools/web/build_vercel.sh`, poi `python3 -m http.server -d sito 8000`
e apri <http://localhost:8000/app/>. Attenzione: è collegata al database vero. Con
`flutter run -d chrome` serve prima, una volta, `tools/web/agora_sdk.sh` (per la stanza vocale).
I test che girano nel browser: `flutter test --platform chrome test/web`; il service worker
delle notifiche si prova con `node tools/web/test/notifiche_test.js` (Playwright e Chrome).

## Il modulo di candidatura

Il modulo usa [FormSubmit](https://formsubmit.co) (gratuito, senza registrazione): le candidature
arrivano come email in tabella a **milanacproclub@proton.me**, con risposta automatica al candidato.

- **Attivazione, una volta sola**: alla prima candidatura inviata dal sito, FormSubmit manda a
  milanacproclub@proton.me un'email *"Activate form"*: va aperta e va premuto **Activate**. Da
  quel momento le candidature arrivano normalmente. Finché non si attiva, non arriva nulla.
- **Se FormSubmit non risponde**: l'invio parte in background e il candidato resta sulla pagina.
  Dopo un errore del server o della rete si riprova una volta da soli; se non va, compare un
  messaggio con **Riprova** e un link che apre un'email al club già scritta con tutti i campi,
  e il modulo resta compilato. Se il modulo non è ancora attivato lo dice. Si prova con
  `node tools/web/test/modulo_test.js` (FormSubmit simulato, nessuna email inviata).
- La risposta a una candidatura si fa con *Rispondi*: l'email del candidato è già il mittente a
  cui si risponde.
- Protezione dallo spam: campo trappola nascosto; il captcha è disattivato per non interrompere
  il percorso (`_captcha`), si può riattivare mettendo `true`.
- Per cambiare indirizzo: in `sito/index.html` sostituisci l'email in `action` e `data-endpoint`
  del `<form id="candidatura">` e nel piè di pagina.

## Aggiornare i testi

Tutto è in `sito/index.html`: titoli, storia, regole, squadre, provino, FAQ, organigramma e
modulo. Si modifica il file, si salva su `main` e Vercel ripubblica. Le immagini vanno in
`sito/img/` (le schermate dell'app nel collage sono dimostrative: quando ci saranno partite vere
basta sostituire `app-prossima.jpg`, `app-lavagna.jpg` e `app-risultato.jpg`).

Per provarlo in locale: `python3 -m http.server -d sito 8000` e apri <http://localhost:8000>.
