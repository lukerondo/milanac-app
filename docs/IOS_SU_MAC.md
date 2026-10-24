# App per iPhone: compilarla su un Mac e mandarla su TestFlight

Passo passo, per chi compila dal proprio Mac. Senza Mac c'è Codemagic (vedi
`docs/PUBBLICAZIONE.md` §4): fa le stesse cose nel cloud.

## Cosa serve (una volta sola)

- Un **Mac** con macOS aggiornato e circa 30 GB liberi.
- **Xcode** (dal Mac App Store, l'ultima versione). Aprilo una volta e accetta i componenti
  aggiuntivi che propone.
- L'**account Apple Developer** del club (a pagamento) e l'app già creata su App Store Connect
  (`docs/PUBBLICAZIONE.md` §4, punti 1 e 2: App ID `com.milanacproclub.milanac` con *Push
  Notifications* e *Sign in with Apple*).
- **Flutter 3.47** (la versione stabile usata per l'app): scaricalo da
  https://docs.flutter.dev/get-started/install/macos/mobile-ios, scompattalo in
  `~/development/flutter` e aggiungi `~/development/flutter/bin` al PATH (la guida di Flutter
  spiega come). Controlla con `flutter --version`.
- **CocoaPods** (gestisce le librerie iOS): nel Terminale `brew install cocoapods` (con Homebrew)
  oppure `sudo gem install cocoapods`.
- Nel Terminale, una volta: `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`
  e `sudo xcodebuild -runFirstLaunch`.

## Il progetto sul Mac

Copia la cartella `milanac-app` sul Mac (per esempio nella cartella Inizio, `~/milanac-app`).
In alternativa la prendi da GitHub:

```bash
git clone https://github.com/lukerondo/milanac-app.git
cd milanac-app
git checkout claude/chat-voce-carte-fut
```

## Compilare

Nel Terminale, dalla cartella del progetto:

```bash
cd ~/milanac-app
flutter pub get
cd ios && pod install --repo-update && cd ..
open ios/Runner.xcworkspace
```

In Xcode (si apre con l'ultimo comando): a sinistra **Runner** → scheda **Signing & Capabilities**
→ spunta *Automatically manage signing* e scegli il **Team** del club. Il *Bundle Identifier*
deve restare `com.milanacproclub.milanac`. Poi chiudi Xcode e nel Terminale:

```bash
flutter build ipa --release --dart-define-from-file=env/prod.json --build-number=2
```

Il file pronto è in `build/ios/ipa/` (estensione `.ipa`). Il **numero di build** va aumentato a
ogni invio (2, 3, 4…): TestFlight rifiuta un numero già usato.

## Mandarla su TestFlight

1. Installa **Transporter** dal Mac App Store, accedi con l'Apple ID del club.
2. Trascina il file `.ipa` in Transporter e premi **Consegna**.
3. Su appstoreconnect.apple.com → la tua app → **TestFlight**: dopo 10–30 minuti di elaborazione
   la build compare. Aggiungi i tester:
   - *Interni* (chi ha accesso ad App Store Connect, fino a 100): subito;
   - *Esterni* (fino a 10.000, anche con un link pubblico): la prima volta Apple fa una breve
     revisione.
4. Ogni giocatore installa l'app **TestFlight** dall'App Store e accetta l'invito.

## Da sapere

- **iOS 15.5 o più recente** (lo chiede lo scontorno delle foto della carta, Google ML Kit).
- **Simulatore**: sui Mac con chip Apple il simulatore di iOS 26 non apre le librerie di ML Kit;
  si prova su un iPhone vero (o con il ritocco descritto nel README di `google_mlkit_commons`).
- **Notifiche push**: arrivano solo dopo aver configurato Firebase e la chiave APNs
  (`docs/PUBBLICAZIONE.md` §1). Senza, l'app funziona lo stesso ma non avvisa.
- Se `pod install` si lamenta delle versioni: `cd ios && pod repo update && pod install`.
- Se Xcode non trova il Team o i profili: Xcode → Settings → Accounts → aggiungi l'Apple ID
  del club.
