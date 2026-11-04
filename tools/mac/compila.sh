#!/usr/bin/env bash
# Compila MILANAC su un Mac: l'IPA ad hoc per gli iPhone registrati e l'app per Mac in un DMG.
# Gli stessi passaggi dei workflow iPhone e Mac di GitHub, ma con l'account Apple di Xcode.
# Guida completa: docs/COMPILA_SU_MAC.md.
#
# Uso (dalla cartella del progetto):
#   TEAM_ID=XXXXXXXXXX tools/mac/compila.sh iphone   → dist/MILANAC.ipa
#   tools/mac/compila.sh mac                         → dist/MILANAC.dmg
#   TEAM_ID=XXXXXXXXXX tools/mac/compila.sh tutto    → tutti e due
#   tools/mac/compila.sh controlla                   → solo il controllo degli strumenti
#
# Variabili facoltative per il Mac (distribuzione senza avvisi, vedi la guida):
#   MAC_FIRMA="Developer ID Application: Nome Cognome (XXXXXXXXXX)"
#   NOTARY_PROFILE=milanac   (profilo creato con: xcrun notarytool store-credentials milanac ...)
set -euo pipefail

FLUTTER_VERSIONE="3.47.7"
BUNDLE_ID="com.milanacproclub.milanac"
cd "$(dirname "$0")/../.."
RADICE=$(pwd)
DIST="$RADICE/dist"

ok() { printf '  ✓ %s\n' "$1"; }
errore() { printf '\n✗ %s\n' "$1" >&2; exit 1; }
passo() { printf '\n▶ %s\n' "$1"; }

controlla() {
  passo "Controllo degli strumenti"
  [ "$(uname)" = Darwin ] || errore "Serve un Mac (macOS)."
  xcode-select -p >/dev/null 2>&1 || errore "Manca Xcode: installalo dall'App Store, aprilo una volta, poi rilancia."
  xcodebuild -version >/dev/null 2>&1 || errore "Xcode non è pronto: esegui 'sudo xcodebuild -license accept' e 'sudo xcodebuild -runFirstLaunch'."
  ok "$(xcodebuild -version | head -1)"
  command -v python3 >/dev/null || errore "Manca python3 (arriva con gli strumenti di Xcode: xcode-select --install)."
  ok "python3"
  if ! command -v pod >/dev/null; then
    errore "Manca CocoaPods: installa Homebrew (https://brew.sh) e poi 'brew install cocoapods'."
  fi
  ok "CocoaPods $(pod --version)"
  # Flutter: la versione fissa del progetto; se manca la scarica in ~/flutter-$FLUTTER_VERSIONE.
  if ! command -v flutter >/dev/null || ! flutter --version 2>/dev/null | grep -q "Flutter $FLUTTER_VERSIONE "; then
    local dir="$HOME/flutter-$FLUTTER_VERSIONE"
    if [ ! -x "$dir/bin/flutter" ]; then
      passo "Scarico Flutter $FLUTTER_VERSIONE in $dir (una volta sola, qualche minuto)"
      git clone --depth 1 --branch "$FLUTTER_VERSIONE" https://github.com/flutter/flutter.git "$dir"
    fi
    export PATH="$dir/bin:$PATH"
  fi
  flutter --version 2>/dev/null | grep -q "Flutter $FLUTTER_VERSIONE " || errore "Flutter $FLUTTER_VERSIONE non disponibile."
  ok "Flutter $FLUTTER_VERSIONE"
  flutter config --no-analytics >/dev/null 2>&1 || true
}

dipendenze() {
  passo "Dipendenze del progetto"
  flutter pub get
}

iphone() {
  [ -n "${TEAM_ID:-}" ] || errore "Indica il Team ID dell'account Apple: TEAM_ID=XXXXXXXXXX tools/mac/compila.sh iphone (developer.apple.com → Membership)."
  [[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || errore "Il Team ID è di 10 lettere maiuscole e cifre (ora: $TEAM_ID)."
  # Da Xcode 15 la piattaforma iOS si scarica a parte: senza, l'archivio si ferma con
  # "iOS … is not installed".
  if ! xcrun simctl runtime list 2>/dev/null | grep -q "iOS"; then
    passo "Scarico la piattaforma iOS per Xcode (una volta sola)"
    xcodebuild -downloadPlatform iOS
  fi
  passo "Archivio per iPhone (senza firma)"
  flutter build ipa --release --no-codesign --dart-define-from-file=env/prod.json
  local app="build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app"
  # Come l'APK: via le estensioni di Agora che la stanza vocale (solo audio) non usa.
  python3 tools/ios/senza_estensioni_agora.py "$app"

  passo "Firma ad hoc con l'account Apple di Xcode (team $TEAM_ID)"
  local opzioni
  opzioni="$(mktemp -d)/ExportOptions.plist"
  cat > "$opzioni" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>release-testing</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
PLIST
  rm -rf build/ios/ipa
  # -allowProvisioningUpdates: Xcode crea o aggiorna da solo certificato e profilo Ad Hoc con
  # tutti gli iPhone registrati sull'account (developer.apple.com → Devices).
  xcodebuild -exportArchive \
    -archivePath build/ios/archive/Runner.xcarchive \
    -exportOptionsPlist "$opzioni" \
    -exportPath build/ios/ipa \
    -allowProvisioningUpdates
  rm -f "$opzioni"
  mkdir -p "$DIST"
  cp build/ios/ipa/*.ipa "$DIST/MILANAC.ipa"

  passo "Verifica dell'IPA"
  local verifica
  verifica=$(mktemp -d)
  unzip -q "$DIST/MILANAC.ipa" -d "$verifica"
  local dentro="$verifica/Payload/Runner.app"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$dentro/Info.plist")" = "$BUNDLE_ID" ] \
    || errore "Identificativo dell'app inatteso."
  codesign --verify --deep --strict "$dentro"
  security cms -D -i "$dentro/embedded.mobileprovision" > "$verifica/profilo.plist"
  local n
  n=$(/usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$verifica/profilo.plist" | grep -c '^ ' || true)
  rm -rf "$verifica"
  ok "MILANAC.ipa firmato ad hoc per $n iPhone, $(du -h "$DIST/MILANAC.ipa" | cut -f1)"
}

mac() {
  passo "App per Mac"
  flutter build macos --release --dart-define-from-file=env/prod.json
  local app="build/macos/Build/Products/Release/MILANAC.app"
  local ent="macos/Runner/Release.entitlements"
  xattr -cr "$app"
  if [ -n "${MAC_FIRMA:-}" ]; then
    # Developer ID: prima tutto quello che sta dentro l'app, poi l'app, con il runtime protetto
    # (obbligatorio per la notarizzazione) e i permessi dell'app (sandbox, rete, microfono, file).
    passo "Firma Developer ID: $MAC_FIRMA"
    find "$app/Contents/Frameworks" -depth \( -name "*.framework" -o -name "*.dylib" \) -print0 \
      | while IFS= read -r -d '' f; do
          codesign --force --timestamp --options runtime --sign "$MAC_FIRMA" "$f"
        done
    codesign --force --timestamp --options runtime --entitlements "$ent" --sign "$MAC_FIRMA" "$app"
  else
    # Senza certificato: firma ad-hoc come su GitHub. Chi la apre la prima volta usa tasto destro → Apri.
    codesign --force --deep --sign - "$app"
    codesign --force --sign - --entitlements "$ent" "$app"
  fi
  codesign --verify --deep --strict --verbose=1 "$app"

  if [ -n "${MAC_FIRMA:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    passo "Notarizzazione dell'app da parte di Apple (qualche minuto)"
    local zip
    zip=$(mktemp -d)/MILANAC.zip
    ditto -c -k --keepParent "$app" "$zip"
    xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    rm -f "$zip"
  fi

  passo "DMG"
  mkdir -p "$DIST"
  local cartella
  cartella=$(mktemp -d)
  ditto "$app" "$cartella/MILANAC.app"
  ln -s /Applications "$cartella/Applications"
  rm -f "$DIST/MILANAC.dmg"
  local n=0
  # hdiutil a volte risponde "Resource busy": si riprova.
  until hdiutil create -volname MILANAC -srcfolder "$cartella" -format UDZO -ov "$DIST/MILANAC.dmg"; do
    n=$((n + 1))
    [ "$n" -lt 3 ] || errore "hdiutil non riesce a creare il DMG."
    sleep 10
  done
  rm -rf "$cartella"
  if [ -n "${MAC_FIRMA:-}" ]; then
    codesign --force --timestamp --sign "$MAC_FIRMA" "$DIST/MILANAC.dmg"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
      xcrun notarytool submit "$DIST/MILANAC.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
      xcrun stapler staple "$DIST/MILANAC.dmg"
    fi
  fi
  hdiutil verify "$DIST/MILANAC.dmg" >/dev/null
  ok "MILANAC.dmg, $(du -h "$DIST/MILANAC.dmg" | cut -f1)"
}

case "${1:-}" in
  controlla) controlla ;;
  iphone) controlla; dipendenze; iphone ;;
  mac) controlla; dipendenze; mac ;;
  tutto) controlla; dipendenze; iphone; mac ;;
  *)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
printf '\nFatto. I file sono in %s\n' "$DIST"
