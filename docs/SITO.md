# Il sito del club (sito/)

Il sito di MILANAC Pro Club è una sola pagina statica: `sito/index.html` con dentro stile e
script, più le cartelle `img/`, `video/` e `audio/`. Non c'è niente da compilare: si pubblica la
cartella così com'è. Le animazioni (GSAP) e i caratteri (Google Fonts) arrivano da CDN gratuite.

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
poi si aggiorna l'indirizzo nei tag `og:url`, `og:image` e `canonical` di `sito/index.html`.

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
