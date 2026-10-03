# Pubblicazione su Google Play e App Store

Identificativo dell'app (Android e iOS): **`com.milanacproclub.milanac`**
Nome: **MILANAC** · Versione: in `pubspec.yaml` (`version: 1.0.0+1`)

---

## 1. Notifiche push (Firebase, gratuito)

1. https://console.firebase.google.com → **Aggiungi progetto** → nome `milanac` (Analytics: non serve).
2. **Aggiungi app → Android**: package `com.milanacproclub.milanac` → scarica `google-services.json`
   (non va messo nel repository: ci servono solo alcuni valori, vedi punto 4).
3. **Aggiungi app → iOS**: bundle ID `com.milanacproclub.milanac` → scarica `GoogleService-Info.plist`.
4. Copia i valori in `env/prod.json` (sono configurazioni pubbliche, possono stare nel repository):

   | Chiave in `env/prod.json` | Dove si trova |
   |---|---|
   | `FIREBASE_PROJECT_ID` | `project_id` (google-services.json) |
   | `FIREBASE_SENDER_ID` | `project_number` (google-services.json) |
   | `FIREBASE_API_KEY_ANDROID` | `client[0].api_key[0].current_key` |
   | `FIREBASE_APP_ID_ANDROID` | `client[0].client_info.mobilesdk_app_id` |
   | `FIREBASE_API_KEY_IOS` | `API_KEY` (GoogleService-Info.plist) |
   | `FIREBASE_APP_ID_IOS` | `GOOGLE_APP_ID` (GoogleService-Info.plist) |

5. **Invio delle notifiche dai job di GitHub**: Firebase → ⚙️ Impostazioni progetto → **Account di servizio** →
   *Genera nuova chiave privata* → si scarica un file JSON. Copia **tutto il contenuto** in un nuovo secret
   di GitHub chiamato **`FIREBASE_SERVICE_ACCOUNT`**. (È una chiave segreta: non metterla nel repository.)
6. **iPhone**: su developer.apple.com → *Keys* → nuova chiave con **Apple Push Notifications service (APNs)** →
   scarica il `.p8` → Firebase → Impostazioni → **Cloud Messaging** → *Configurazione app Apple* → carica la chiave
   (Key ID e Team ID).

7. **Notifiche personali** (formazione, chat): dopo aver creato il secret `FIREBASE_SERVICE_ACCOUNT`
   vai su GitHub → **Actions → Funzioni → Run workflow**. Il workflow passa la chiave alla funzione
   Supabase `notify` e la collega al database. Da quel momento le notifiche personali partono da sole.

Notifiche a tutto il club (argomento `milanac`, solo ai membri approvati):
- **Nuovo aggiornamento FC 27** – dopo la raccolta notizie (ogni 3 ore)
- **Nuovo evento in calendario** – entro 3 ore dalla creazione
- **Promemoria presenze** – ogni giorno alle ~15:45 se in serata c'è partita/allenamento

Notifiche personali (funzione `notify`, a ogni telefono registrato):
- **Formazione pubblicata** – ai giocatori di quella squadra: "giochi DC titolare" o "parti dalla panchina"
- **Messaggi in chat** – a tutti tranne l'autore e chi ha silenziato il canale; ritardi e assenze
  arrivano in automatico nel canale *Presenze*

Prove manuali: Actions → *Notizie* o *Promemoria presenze* → Run workflow con "Prova".

## 2. Privacy (obbligatoria per entrambi gli store)

1. In `env/prod.json` imposta `CONTACT_EMAIL` (email del club).
2. Pubblica il testo di `assets/legal/privacy.md` (sostituendo `{{EMAIL}}`) come **Gist pubblico**
   su https://gist.github.com (gratuito) e usa il suo link come *URL dell'informativa privacy* negli store.
   La stessa informativa è nell'app: menu → **Privacy**.
3. Nell'app è presente **Elimina il mio account** (richiesto da Apple) – menu laterale.

## 3. Android – Google Play

### Chiave di firma (una volta sola, da conservare per sempre!)
Su un computer con Java installato:
```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias milanac
base64 -w0 upload-keystore.jks > keystore.txt     # su Mac: base64 -i upload-keystore.jks -o keystore.txt
```
Secrets di GitHub (Settings → Secrets and variables → Actions):
`ANDROID_KEYSTORE_BASE64` (contenuto di keystore.txt), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` (`milanac`), `ANDROID_KEY_PASSWORD`.
⚠️ Salva `upload-keystore.jks` e le password in un posto sicuro (es. gestore password): senza non potrai
pubblicare aggiornamenti (in quel caso si può chiedere a Google il reset della chiave di caricamento).

### Build
Actions → **Rilascio Android** → Run workflow → scarica l'artifact `milanac-android-N` (file `.aab`).

### Play Console
1. **Crea app** → nome "MILANAC Pro Club", lingua italiano, App, Gratuita.
2. **Scheda dello store**: testi qui sotto, icona 512×512 (`assets/icon/icon.png` ridimensionata),
   grafica in primo piano 1024×500, almeno 2 screenshot del telefono.
3. **Contenuti dell'app**: informativa privacy (link Gist), nessuna pubblicità, classificazione dei contenuti
   (questionario), pubblico di destinazione (13+ consigliato), **Sicurezza dei dati** (vedi sotto).
4. **Test chiuso**: carica l'.aab. ⚠️ Gli account sviluppatore personali creati dopo novembre 2023 devono
   fare un test chiuso con **almeno 12 tester per 14 giorni consecutivi** prima di poter pubblicare in
   produzione: invita i giocatori del club come tester (via email Google).
5. Dopo i 14 giorni: **Produzione** → nuova release → invia per la revisione.

Sicurezza dei dati (risposte):
- Raccoglie: nome, email, foto/video (caricati dal Direttivo), ID dispositivo per notifiche.
- Finalità: funzionalità dell'app, gestione account. Nessuna condivisione con terze parti per pubblicità.
- Dati criptati in transito: sì. L'utente può chiedere l'eliminazione: sì (dall'app).

## 4. iOS – App Store

1. developer.apple.com → *Identifiers* → App ID `com.milanacproclub.milanac` con le capability
   **Push Notifications** e **Sign in with Apple**.
2. appstoreconnect.apple.com → **Le mie app → +** → nuova app iOS, bundle `com.milanacproclub.milanac`, SKU `milanac`.
3. App Store Connect → *Utenti e accesso* → **Integrazioni → Chiavi API** → genera chiave (ruolo *App Manager*),
   scarica il `.p8` (Issuer ID e Key ID).
4. https://codemagic.io (gratuito: 500 min/mese su Mac) → accedi con GitHub → aggiungi `milanac-app` →
   *Teams → Integrations → App Store Connect* → aggiungi la chiave con il nome **`MILANAC ASC`**.
5. Codemagic → *Code signing identities*: genera/carica il certificato di distribuzione (Codemagic può crearlo
   automaticamente con la chiave API).
6. Avvia il workflow **iOS → TestFlight** (file `codemagic.yaml`): la build arriva su TestFlight.
7. App Store Connect → compila la scheda (testi sotto, screenshot 6,7" e 6,5"), **Privacy dell'app**,
   URL privacy, e invia per la revisione.

⚠️ **Account per i revisori Apple**: l'app richiede l'approvazione del Direttivo, quindi Apple non potrebbe
entrare. Crea un account di prova (es. un account Google dedicato), fai login una volta, approvalo come
*Giocatore* e scrivi email e password nelle **Note per la revisione** di App Store Connect (idem nella sezione
*Accesso all'app* della Play Console).

## 5. Testi per gli store

**Nome**: MILANAC Pro Club
**Sottotitolo / breve descrizione (80 car.)**: L'app ufficiale del MILANAC Pro Club: rosa, partite, presenze e trofei.

**Descrizione**:
> L'app ufficiale del MILANAC Pro Club, il club rossonero di EA SPORTS FC Pro Clubs. Milano siamo noi!
>
> • Notizie su tornei FVPA, aggiornamenti di FC 27, Ultimate Team e Pro Clubs, con avviso quando esce un nuovo aggiornamento del gioco
> • Rosa completa con ruoli e data di ingresso
> • Formazione sul campo stile San Siro
> • Calendario di partite, allenamenti e riunioni
> • Risultati con gol, foto e highlights delle partite
> • Albo d'oro con la bacheca dei trofei stagione per stagione
> • Presenze della serata, con orario di arrivo e storico
> • Regolamento e storia del club
>
> L'accesso è riservato ai membri del club, approvati dal Direttivo.

**Parole chiave (iOS)**: pro club, fc 27, ea fc, fvpa, clubs, milan, squadra, presenze, formazione
**Categoria**: Sport
