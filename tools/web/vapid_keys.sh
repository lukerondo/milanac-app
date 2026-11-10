#!/usr/bin/env bash
# Genera la coppia di chiavi VAPID per le notifiche nel browser (Web Push, RFC 8292).
# Stampa due righe:
#   VAPID_PUBLIC_KEY=<punto P-256 non compresso, base64url: è la chiave data ai browser>
#   VAPID_PRIVATE_KEY=<PKCS#8 in base64: resta solo tra i segreti della funzione notify>
# La usa il workflow "Funzioni" la prima volta; la privata non va mai scritta nel repository.
set -euo pipefail

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
openssl ecparam -name prime256v1 -genkey -noout -out "$dir/ec.pem" 2>/dev/null
# Gli ultimi 65 byte della chiave pubblica DER sono il punto non compresso (04 || X || Y).
public=$(openssl ec -in "$dir/ec.pem" -pubout -outform DER 2>/dev/null | tail -c 65 | base64 -w0 | tr '+/' '-_' | tr -d '=')
private=$(openssl pkcs8 -topk8 -nocrypt -in "$dir/ec.pem" -outform DER | base64 -w0)
if [ "${#public}" -ne 87 ] || [ -z "$private" ]; then
  echo "Chiavi VAPID non generate" >&2
  exit 1
fi
echo "VAPID_PUBLIC_KEY=$public"
echo "VAPID_PRIVATE_KEY=$private"
