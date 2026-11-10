#!/usr/bin/env bash
# Scarica l'SDK Web di Agora (stanza vocale nel browser) in web/agora/, da dove
# `flutter build web` lo copia accanto all'app. Versione fissa e controllo dell'impronta:
# il file non sta nel repository. Lo lancia tools/web/build_vercel.sh; a mano serve una
# volta prima di `flutter run -d chrome`.
set -euo pipefail

VERSIONE="4.24.9"
# sha256 del pacchetto pubblicato su npm (agora-rtc-sdk-ng, licenza MIT).
IMPRONTA="a8f71d89edabaafb14f28ace5c99be36137de2b43af0ac9a04d836bffc22e093"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dest="$root/web/agora"
file="$dest/AgoraRTC_N-production.js"
marca="$dest/.versione"

if [ -f "$file" ] && [ "$(cat "$marca" 2>/dev/null)" = "$VERSIONE" ]; then
  echo "SDK Web di Agora $VERSIONE già presente"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 -o "$tmp/sdk.tgz" \
  "https://registry.npmjs.org/agora-rtc-sdk-ng/-/agora-rtc-sdk-ng-$VERSIONE.tgz"
trovata="$(sha256sum "$tmp/sdk.tgz" | cut -d' ' -f1)"
if [ "$trovata" != "$IMPRONTA" ]; then
  echo "SDK Web di Agora $VERSIONE: impronta inattesa ($trovata)"
  exit 1
fi
tar -xzf "$tmp/sdk.tgz" -C "$tmp" package/AgoraRTC_N-production.js
mkdir -p "$dest"
mv "$tmp/package/AgoraRTC_N-production.js" "$file"
echo "$VERSIONE" > "$marca"
echo "SDK Web di Agora $VERSIONE pronto in web/agora ($(du -h "$file" | cut -f1))"
