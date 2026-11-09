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
  La Root Directory è già `sito`. Da quel momento ogni modifica unita in `main` va online da sola.
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
- **Cosa non c'è nel browser** (resta nell'app sul telefono): la stanza vocale, i messaggi
  vocali e la registrazione dei replay, le notifiche, la musica scelta dal proprio dispositivo.
- **Aggiornarla**: dopo ogni modifica all'app unita in `main` va ripubblicato il sito, come
  sopra. La web app non si aggiorna da sola finché Vercel non è collegato al repository.

Per provarla in locale: `tools/web/build_vercel.sh`, poi `python3 -m http.server -d sito 8000`
e apri <http://localhost:8000/app/>. Attenzione: è collegata al database vero.

## Il modulo di candidatura

Il modulo usa [FormSubmit](https://formsubmit.co) (gratuito, senza registrazione): le candidature
arrivano come email in tabella a **milanacproclub@proton.me**, con risposta automatica al candidato.

- **Attivazione, una volta sola**: alla prima candidatura inviata dal sito, FormSubmit manda a
  milanacproclub@proton.me un'email *"Activate form"*: va aperta e va premuto **Activate**. Da
  quel momento le candidature arrivano normalmente. Finché non si attiva, non arriva nulla.
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
