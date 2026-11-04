# Compilare MILANAC sul Mac (iPhone e Mac)

Con questa guida, da un Mac si ottengono:
- `MILANAC.ipa`: l'app per gli **iPhone registrati** sull'account sviluppatore Apple (si
  distribuisce con un sito come Diawi);
- `MILANAC.dmg`: l'app per **Mac**, da trascinare in Applicazioni.

Lo script `tools/mac/compila.sh` fa gli stessi passaggi dei workflow *iPhone* e *Mac* di GitHub,
che continuano a pubblicare da soli IPA e DMG nelle release a ogni aggiornamento di `main`: compilare
sul Mac serve per farlo in autonomia, con l'account Apple collegato a Xcode.

## 1. Cosa serve (una volta sola)

1. Un Mac con **macOS 15 (Sequoia) o più recente** e almeno **40 GB liberi**.
2. **Xcode** dall'App Store. Aprilo una volta, accetta la licenza e lascia che installi i
   componenti; quando chiede le piattaforme scegli anche **iOS**.
3. **L'account sviluppatore in Xcode**: Xcode → *Settings* (⌘,) → *Accounts* → **+** → *Apple ID* →
   accedi con l'Apple ID dell'account sviluppatore del club. Deve comparire il team con il ruolo
   *Admin* o *Account Holder*.
4. Apri l'app **Terminale** (Applicazioni → Utility) e incolla, una riga alla volta:
   ```
   xcode-select --install
   sudo xcodebuild -license accept
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   brew install cocoapods
   ```
   (la terza riga installa Homebrew; alla fine segui le due righe "Next steps" che stampa).
   **Flutter non serve installarlo**: lo script scarica da solo la versione giusta (3.47.7).
5. Il **Team ID** dell'account: developer.apple.com → *Account* → *Membership details* →
   *Team ID* (10 caratteri, per esempio `AB12CD34EF`).

## 2. Il progetto

- **Cartella zip**: scompattala, per esempio in *Documenti*, così hai `Documenti/milanac-app`.
- **Oppure da GitHub** (comodo per gli aggiornamenti):
  ```
  cd ~/Documents
  git clone https://github.com/lukerondo/milanac-app.git
  ```
  e per aggiornare in futuro: `cd ~/Documents/milanac-app && git pull`.

## 3. Gli iPhone dei ragazzi

L'IPA si installa **solo** sugli iPhone registrati sull'account (massimo 100 l'anno).
1. Ogni membro apre da **Safari** sull'iPhone <https://udid.tech>, installa il profilo che propone
   (Impostazioni → Profilo scaricato) e ti manda il suo **UDID**.
2. Registralo: developer.apple.com → *Certificates, Identifiers & Profiles* → **Devices** → **+** →
   piattaforma iOS, un nome (es. "Fabio") e l'UDID.
   In alternativa aggiungi la riga `Nome;UDID` al secret `IOS_DISPOSITIVI` su GitHub e lancia il
   workflow *iPhone*: registra lui gli iPhone sull'account.
3. Dopo ogni nuovo iPhone registrato si **ricompila** l'IPA: il profilo nuovo li comprende tutti.

## 4. Compilare

Nel Terminale, dalla cartella del progetto:

```
cd ~/Documents/milanac-app
TEAM_ID=AB12CD34EF tools/mac/compila.sh iphone     # → dist/MILANAC.ipa
tools/mac/compila.sh mac                           # → dist/MILANAC.dmg
TEAM_ID=AB12CD34EF tools/mac/compila.sh tutto      # → tutti e due
```

(sostituisci `AB12CD34EF` con il tuo Team ID). La prima volta ci vogliono 15-20 minuti (scarica
Flutter e le librerie), le volte dopo 5-10. Alla fine i file sono nella cartella **`dist`**
dentro il progetto. `tools/mac/compila.sh controlla` verifica solo che gli strumenti ci siano.

Lo script, per l'iPhone: compila l'archivio, toglie le estensioni di Agora che la stanza vocale non
usa (come per l'APK: l'IPA pesa circa 32 MB invece di 58), e lo fa firmare a Xcode con il profilo
**Ad Hoc** di tutti gli iPhone registrati, poi controlla firma, identificativo e numero di iPhone.

## 5. Distribuire

**iPhone**: carica `dist/MILANAC.ipa` su <https://www.diawi.com> (con l'account gratuito fino a
50 MB) e manda il link: si apre da **Safari** sull'iPhone → *Installa*. Se l'iPhone dice che l'app
non si può installare, quasi sempre quell'iPhone non era registrato quando hai compilato: registralo
(punto 3) e ricompila.

**Mac**: manda `dist/MILANAC.dmg`. Chi lo riceve lo apre e trascina MILANAC in Applicazioni. Con la
firma normale (ad-hoc) la prima volta il Mac la blocca: tasto destro sull'app → **Apri** → **Apri**
(su macOS 15 e successivi: Impostazioni di Sistema → Privacy e sicurezza → **Apri comunque**).

### Mac senza avvisi (facoltativo): Developer ID e notarizzazione

Con l'account sviluppatore l'app per Mac si può firmare e far certificare da Apple, così si apre
con un doppio clic e basta.
1. Xcode → *Settings* → *Accounts* → il team → **Manage Certificates** → **+** →
   **Developer ID Application**.
2. Una *password specifica per app*: appleid.apple.com → Accesso e sicurezza → Password specifiche
   per le app → **+** (nome "notarizzazione").
3. Nel Terminale, una volta sola (con i tuoi dati):
   ```
   xcrun notarytool store-credentials milanac --apple-id TUA@EMAIL --team-id AB12CD34EF --password PASSWORD-SPECIFICA
   ```
4. Il nome esatto del certificato: `security find-identity -v -p codesigning` (la riga
   "Developer ID Application: …").
5. Compila così:
   ```
   MAC_FIRMA="Developer ID Application: Nome Cognome (AB12CD34EF)" NOTARY_PROFILE=milanac tools/mac/compila.sh mac
   ```
   Lo script firma ogni libreria e l'app con il runtime protetto, manda l'app e il DMG ad Apple per
   la notarizzazione (qualche minuto) e ci "aggrafa" il certificato.

Questo percorso è la procedura standard di Apple ma non è ancora stato provato su questo progetto:
se Apple rifiuta la notarizzazione, il comando `xcrun notarytool log …` che compare nel messaggio
dice quale file non va.

## Problemi frequenti

| Messaggio | Cosa fare |
|---|---|
| `Manca Xcode` / `Xcode non è pronto` | Apri Xcode una volta, poi `sudo xcodebuild -license accept` e `sudo xcodebuild -runFirstLaunch`. |
| `Manca CocoaPods` | `brew install cocoapods` (punto 1.4). |
| `No Accounts` / `requires a development team` / `No profiles for 'com.milanacproclub.milanac'` | L'account sviluppatore non è in Xcode → *Settings* → *Accounts* (punto 1.3), oppure il Team ID è sbagliato. |
| `iOS … is not installed` | Xcode → *Settings* → *Components* → scarica **iOS**. |
| L'IPA si installa su alcuni iPhone e su altri no | Gli altri non erano registrati: punto 3, poi ricompila. |
| `Estensioni di Agora lasciate nell'app` | Avviso, non errore: l'IPA funziona ma pesa di più (oltre i 50 MB di Diawi gratuito). |

Le notifiche push su iPhone e Mac per ora non ci sono (manca la configurazione di Firebase, vedi
`docs/PUBBLICAZIONE.md`).
