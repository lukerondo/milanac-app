# Il sito del club (sito/)

Il sito di MILANAC Pro Club è una sola pagina statica: `sito/index.html` con dentro stile e
script, più le cartelle `img/`, `video/` e `audio/`. Non c'è niente da compilare: si pubblica la
cartella così com'è. Le animazioni (GSAP) e i caratteri (Google Fonts) arrivano da CDN gratuite.

## Pubblicazione su Vercel (gratis)

Il sito è il progetto **milanacproclub** sull'account Vercel del club (piano Hobby), all'indirizzo
<https://milanacproclub.vercel.app>. A pubblicarlo è il workflow **Sito** di GitHub
(`.github/workflows/sito.yml`): a ogni aggiornamento di `main` che tocca `sito/` carica la
cartella su Vercel con la Vercel CLI. Si può lanciare anche a mano da *Actions → Sito → Run
workflow*; alla fine il riepilogo del lavoro mostra l'indirizzo.

Serve, una volta sola, il secret **`VERCEL_TOKEN`**:
1. Su <https://vercel.com>, con l'account del progetto: avatar in alto a destra → *Account
   Settings* → *Tokens* → *Create*. Nome `github-sito`, Scope il team che contiene il progetto
   (quello di Francesco), Expiration *No Expiration* (o un anno: alla scadenza se ne crea un
   altro). Copia il token: Vercel lo mostra una volta sola.
2. Su GitHub: repository → *Settings* → *Secrets and variables* → *Actions* → *New repository
   secret*: nome `VERCEL_TOKEN`, valore il token.
3. *Actions → Sito → Run workflow*. Dopo un minuto il sito è online.

Gli identificativi del progetto nel workflow (`VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`) non sono
segreti. Un dominio proprio, quando ci sarà, si aggiunge su Vercel in *Settings → Domains* del
progetto; poi si aggiorna l'indirizzo nei tag `og:url`, `og:image` e `canonical` di
`sito/index.html`.

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
