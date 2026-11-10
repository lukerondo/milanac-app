#!/usr/bin/env bash
# Compila la web app (la stessa app Flutter, per il browser) dentro sito/app: Vercel la
# pubblica insieme al sito, all'indirizzo /app/. Lo lancia il "buildCommand" di
# sito/vercel.json a ogni pubblicazione; a mano: tools/web/build_vercel.sh
#
# Non servono secret: l'indirizzo di Supabase e la chiave pubblica stanno in env/prod.json.
set -euo pipefail

# La stessa versione dei workflow in .github/workflows.
FLUTTER_VERSION="3.47.7"
FLUTTER_REVISION="abaf9c523780a608bd46686fd5e53740a07077f8"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

# Senza le chiavi l'app partirebbe in demo (dati finti, poteri del Direttivo): mai online.
grep -q '"SUPABASE_URL"' env/prod.json || {
  echo "env/prod.json senza SUPABASE_URL: la web app non si pubblica."
  exit 1
}

if ! command -v flutter >/dev/null 2>&1; then
  sdk="${FLUTTER_HOME:-/tmp/flutter-$FLUTTER_VERSION}"
  if [ ! -x "$sdk/bin/flutter" ]; then
    echo "Scarico Flutter $FLUTTER_VERSION"
    rm -rf "$sdk"
    git clone --quiet --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$sdk"
  fi
  found="$(git -C "$sdk" rev-parse HEAD)"
  if [ "$found" != "$FLUTTER_REVISION" ]; then
    echo "Flutter $FLUTTER_VERSION ha una revisione inattesa: $found"
    exit 1
  fi
  export PATH="$sdk/bin:$PATH"
fi

export CI=true
flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version
flutter pub get --enforce-lockfile

# La stanza vocale nel browser usa l'SDK Web di Agora: va accanto all'app.
"$root/tools/web/agora_sdk.sh"

out="$root/sito/app"
rm -rf "$out"
# --no-web-resources-cdn: il motore grafico si scarica dal nostro sito, non da Google.
flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn \
  --base-href /app/ --dart-define-from-file=env/prod.json --output "$out"

# Simboli di debug del motore grafico: al browser non servono.
find "$out/canvaskit" -name '*.symbols' -delete
# Senza l'SDK la stanza vocale nel browser non partirebbe: meglio non pubblicare.
[ -s "$out/agora/AgoraRTC_N-production.js" ] && [ -s "$out/stanza_vocale.js" ] || {
  echo "Nella web app manca la stanza vocale (SDK di Agora o stanza_vocale.js)."
  exit 1
}
rm -f "$out/agora/.versione"
echo "Web app pronta: $(du -sh "$out" | cut -f1) in sito/app"
