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

1. In `env/prod.json` imposta `CONTACT_EMAIL` (email del club). Finché è vuoto l'informativa
   nell'app dice di scrivere al Direttivo nella chat del club; per gli store serve l'email.
2. Pubblica il testo di `assets/legal/privacy.md` (sostituendo `{{EMAIL}}`) come **Gist pubblico**
   su https://gist.github.com (gratuito) e usa il suo link come *URL dell'informativa privacy* negli store.
   La stessa informativa è nell'app: foto in alto a destra → Impostazioni → **Privacy**.
3. Nell'app è presente **Elimina il mio account** (richiesto da Apple) – Impostazioni → Account.
4. **Servizio in primo piano di tipo microfono** (stanza vocale con lo schermo spento): su Google
   Play va dichiarato in *Play Console → Contenuti dell'app → Servizi in primo piano* scegliendo
   "Microfono" e spiegando l'uso ("chiamata vocale di gruppo avviata dall'utente nella chat del
   club"). Su iOS la modalità *audio* in background è già nell'Info.plist.

## 3. Android – Google Play

### Chiave di firma (una volta sola, da conservare per sempre!)
Una sola chiave privata firma sia gli **APK di prova** che i giocatori scaricano (workflow *CI*,
release "APK di prova") sia l'**App Bundle** per Google Play (workflow *Rilascio Android*).
Finché i secret non ci sono, gli APK di prova si firmano con la chiave di prova del repository
(`android/app/apk-di-prova.keystore`, password `android`): è pubblica, quindi chiunque potrebbe
firmare un APK modificato che si installa sopra il nostro come "aggiornamento" e ne eredita la
sessione. Con la chiave privata questo non è più possibile.

1. Su un computer con Java installato crea la chiave (ti chiede una password: sceglila lunga):
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias milanac
   base64 -w0 upload-keystore.jks > keystore.txt     # su Mac: base64 -i upload-keystore.jks -o keystore.txt
   ```
2. Secrets di GitHub (Settings → Secrets and variables → Actions → *New repository secret*):

   | Secret | Valore |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | il contenuto di `keystore.txt` |
   | `ANDROID_KEYSTORE_PASSWORD` | la password della chiave |
   | `ANDROID_KEY_ALIAS` | `milanac` |
   | `ANDROID_KEY_PASSWORD` | la stessa password (keytool usa quella del file anche per la chiave) |

3. Rilancia **Actions → CI → Run workflow**: nel passo *Verifica la firma* deve comparire
   "Firma corretta (chiave privata)". Cancella `keystore.txt` dal computer.

⚠️ **Al cambio di chiave tutti reinstallano una volta.** Il primo APK firmato con la chiave privata
non si installa sopra quello vecchio (Android dice "App non installata" o "pacchetto in conflitto"):
ogni giocatore deve **disinstallare** l'app e installare il nuovo APK, poi rientrare con email e
password (i dati del club restano sul server; si perdono solo le preferenze del telefono, come
l'aspetto chiaro o scuro). Avvisa il club in chat prima di pubblicarlo. Dagli APK successivi gli
aggiornamenti tornano a installarsi sopra.

⚠️ Salva `upload-keystore.jks` e le password in un posto sicuro (es. gestore password): senza non potrai
pubblicare aggiornamenti (in quel caso si può chiedere a Google il reset della chiave di caricamento,
ma gli APK di prova andrebbero reinstallati di nuovo da tutti).

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
- Raccoglie: nome, email, anno di nascita, foto e video, messaggi in-app, registrazioni audio (vocali della
  chat e replay della lavagna, che scadono), ID dispositivo per le notifiche. La stanza vocale passa da Agora
  in tempo reale e non viene registrata.
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

⚠️ **Account per i revisori Apple**: l'app è riservata ai membri del club (registrazione in tre passi e
regolamento da accettare). Crea un account di prova con email e password, completa la registrazione come
*Giocatore* e accetta il regolamento, poi scrivi email e password nelle **Note per la revisione** di App Store
Connect (idem nella sezione *Accesso all'app* della Play Console). Finita la revisione, toglilo dalla Rosa.

### iPhone senza App Store (ad hoc, con gli UDID)

Per far provare l'app ai membri senza App Store né TestFlight: i loro iPhone (UDID) si registrano
sull'account sviluppatore, GitHub compila un IPA firmato per quei telefoni (workflow **iPhone**) e un
sito come [Diawi](https://www.diawi.com) dà il link per installarlo da Safari. Massimo 100 iPhone
l'anno per tipo di dispositivo; profilo e certificato durano un anno.

1. **UDID**: ogni membro apre da Safari sull'iPhone un sito come <https://udid.tech>, installa il
   profilo che propone (Impostazioni → Profilo scaricato) e ti manda il codice UDID.
2. developer.apple.com → *Certificates, IDs & Profiles*:
   - **Devices → +**: un dispositivo per ogni UDID (come nome, quello del giocatore).
   - **Identifiers**: l'App ID `com.milanacproclub.milanac` (se manca, crealo). Push Notifications e
     Sign in with Apple sono facoltativi: se non ci sono, il workflow li toglie dai permessi dell'app.
   - **Certificates → +** → **Apple Distribution**: sul Mac *Accesso Portachiavi → Assistente
     Certificato → Richiedi un certificato da un'Autorità di certificazione* (salvata su disco), carica il
     file, scarica il certificato e aprilo (finisce nel Portachiavi). In *Portachiavi → I miei
     certificati* tasto destro su "Apple Distribution: …" → **Esporta** → `.p12` con una password.
   - **Profiles → +** → **Ad Hoc** → App ID `com.milanacproclub.milanac` → il certificato → **tutti i
     dispositivi** → nome per esempio `MILANAC Ad Hoc` → scarica il `.mobileprovision`.
3. GitHub → *Settings → Secrets and variables → Actions → New repository secret* (dal Terminale del Mac
   `base64 -i FILE | pbcopy` copia il file già pronto da incollare):
   - `IOS_CERTIFICATO_P12`: il `.p12` in base64;
   - `IOS_CERTIFICATO_PASSWORD`: la password del `.p12`;
   - `IOS_PROFILO_ADHOC`: il `.mobileprovision` in base64.
4. GitHub → *Actions → iPhone → Run workflow*: nella release
   [App per iPhone](https://github.com/lukerondo/milanac-app/releases/tag/iphone-di-prova) esce
   `MILANAC.ipa`, firmato per gli iPhone del profilo.
5. Carica `MILANAC.ipa` su Diawi e manda il link: si apre da **Safari** sull'iPhone → *Installa*.
6. **Nuovo membro**: registra il suo UDID (punto 2), modifica il profilo Ad Hoc spuntando il nuovo
   dispositivo, scaricalo, aggiorna il secret `IOS_PROFILO_ADHOC` e rilancia il workflow.

Senza i secret il workflow pubblica `MILANAC-non-firmato.ipa`, da firmare con il proprio certificato e
profilo (per esempio con gli strumenti o i siti che firmano l'IPA per gli UDID).

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
> L'accesso è riservato ai membri del club: ci si registra e si accetta il regolamento del club.

**Parole chiave (iOS)**: pro club, fc 27, ea fc, fvpa, clubs, milan, squadra, presenze, formazione
**Categoria**: Sport
