# Il sito del club (sito/)

Il sito di MILANAC Pro Club è una sola pagina statica: `sito/index.html` con dentro stile e
script, più le cartelle `img/`, `video/` e `audio/`. Non c'è niente da compilare: si pubblica la
cartella così com'è. Le animazioni (GSAP) e i caratteri (Google Fonts) arrivano da CDN gratuite.

## Pubblicare su Vercel (gratis)

Una volta sola:
1. Vai su <https://vercel.com>, **Sign up** → *Continue with GitHub* (l'account GitHub che vede il
   repository `lukerondo/milanac-app`).
2. **Add New…** → **Project** → *Import* accanto a `milanac-app` (se non compare, *Adjust GitHub App
   Permissions* e concedi l'accesso al repository).
3. Nella schermata di configurazione:
   - **Project Name**: `milanacproclub` (diventa l'indirizzo `milanacproclub.vercel.app`, se libero);
   - **Root Directory**: *Edit* → scegli `sito`;
   - **Framework Preset**: *Other*; lascia vuoti Build Command e Output Directory.
4. **Deploy**. Dopo un minuto il sito è online all'indirizzo mostrato (`https://….vercel.app`).

Da lì in poi **ogni aggiornamento di `main` ripubblica il sito da solo** (Vercel segue il
repository). Un dominio proprio, quando ci sarà, si aggiunge in *Settings → Domains*.

Dopo la prima pubblicazione, scrivi l'indirizzo definitivo nei tag `og:image` (deve essere un
indirizzo completo, es. `https://milanacproclub.vercel.app/img/poster.jpg`) così le anteprime su
WhatsApp e sui social mostrano l'immagine.

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
