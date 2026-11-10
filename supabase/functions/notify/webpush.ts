// Web Push (RFC 8030) verso il browser, senza librerie: cifratura del messaggio (RFC 8291,
// contenuto "aes128gcm" dell'RFC 8188) e firma VAPID (RFC 8292) con Web Crypto.
// Usato dalla funzione notify per le notifiche della web app; provato in webpush_test.ts
// con i vettori dell'RFC 8291.

const te = new TextEncoder();

/// I byte come li vuole Web Crypto (i tipi cambiano tra una versione di TypeScript e l'altra).
const src = (bytes: Uint8Array) => bytes as unknown as BufferSource;

export function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

export function fromB64url(text: string): Uint8Array {
  const s = text.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(s + "=".repeat((4 - (s.length % 4)) % 4)), (c) => c.charCodeAt(0));
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

async function hkdf(salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, length: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", src(ikm), "HKDF", false, ["deriveBits"]);
  return new Uint8Array(
    await crypto.subtle.deriveBits(
      { name: "HKDF", hash: "SHA-256", salt: src(salt), info: src(info) }, key, length * 8,
    ),
  );
}

/// L'iscrizione di un browser: indirizzo del servizio push e le due chiavi (base64url).
export type WebPushSubscription = { endpoint: string; p256dh: string; auth: string };

/// I servizi push dei browser (Chrome e derivati, Firefox, Edge, Safari): l'indirizzo lo
/// scrive il browser dell'utente, quindi si spedisce solo a questi.
export function allowedEndpoint(endpoint: string): boolean {
  try {
    const url = new URL(endpoint);
    return url.protocol === "https:" &&
      /(^|\.)(googleapis\.com|push\.services\.mozilla\.com|notify\.windows\.com|push\.apple\.com)$/
        .test(url.hostname);
  } catch (_) {
    return false;
  }
}

/// Dimensione del blocco cifrato: il messaggio sta in un blocco solo.
const RECORD_SIZE = 4096;

/// Lunghezza massima del testo in chiaro (un byte di chiusura e 16 di autenticazione).
export const MAX_PAYLOAD = RECORD_SIZE - 17;

/// Il testo della notifica per il browser: titolo, corpo, dove porta il clic e i dati che
/// servono all'app aperta (per esempio il canale, per non avvisare di ciò che si sta già
/// leggendo). Il corpo si accorcia finché il messaggio cifrato sta comodo in un blocco.
export function webPayload(
  p: { title: string; body: string; route: string; data?: Record<string, string> },
): string {
  let body = p.body.length > 280 ? `${p.body.slice(0, 279)}…` : p.body;
  for (;;) {
    const text = JSON.stringify({ title: p.title, body, route: p.route, data: p.data ?? {} });
    if (te.encode(text).length <= MAX_PAYLOAD - 512 || body.length === 0) return text;
    body = body.slice(0, Math.floor(body.length / 2));
  }
}

/// Cifra [payload] per il browser dell'iscrizione: il corpo della richiesta al servizio push.
/// [salt] e [localKeys] servono solo ai test (vettori dell'RFC): di norma sono casuali.
export async function encrypt(
  sub: { p256dh: string; auth: string },
  payload: Uint8Array,
  opts: { salt?: Uint8Array; localKeys?: CryptoKeyPair } = {},
): Promise<Uint8Array> {
  if (payload.length > MAX_PAYLOAD) throw new Error("messaggio troppo lungo");
  const browserPublic = fromB64url(sub.p256dh);
  const authSecret = fromB64url(sub.auth);
  if (browserPublic.length !== 65 || authSecret.length !== 16) throw new Error("iscrizione non valida");
  const local = opts.localKeys ??
    await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const localPublic = new Uint8Array(await crypto.subtle.exportKey("raw", local.publicKey));
  const browserKey = await crypto.subtle.importKey(
    "raw", src(browserPublic), { name: "ECDH", namedCurve: "P-256" }, false, [],
  );
  const shared = new Uint8Array(
    await crypto.subtle.deriveBits({ name: "ECDH", public: browserKey }, local.privateKey, 256),
  );
  // RFC 8291, 3.4: dalla chiave condivisa e dal segreto del browser alla chiave del messaggio.
  const ikm = await hkdf(
    authSecret, shared, concat(te.encode("WebPush: info\0"), browserPublic, localPublic), 32,
  );
  const salt = opts.salt ?? crypto.getRandomValues(new Uint8Array(16));
  const contentKey = await hkdf(salt, ikm, te.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(salt, ikm, te.encode("Content-Encoding: nonce\0"), 12);
  const key = await crypto.subtle.importKey("raw", src(contentKey), "AES-GCM", false, ["encrypt"]);
  // Un solo blocco: il testo e il byte 2 che lo chiude.
  const cipher = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: src(nonce) }, key, src(concat(payload, new Uint8Array([2]))),
    ),
  );
  // Intestazione (RFC 8188): sale, dimensione del blocco, chiave pubblica di chi spedisce.
  const header = new Uint8Array(16 + 4 + 1 + localPublic.length);
  header.set(salt, 0);
  new DataView(header.buffer).setUint32(16, RECORD_SIZE);
  header[20] = localPublic.length;
  header.set(localPublic, 21);
  return concat(header, cipher);
}

/// Le chiavi VAPID del club: la pubblica (base64url, quella data ai browser) e la privata.
export type Vapid = { publicKey: string; privateKey: CryptoKey; subject: string };

/// La chiave privata VAPID com'è nei segreti della funzione (PKCS#8 in base64).
export function importVapidPrivateKey(pkcs8Base64: string): Promise<CryptoKey> {
  const der = Uint8Array.from(atob(pkcs8Base64.replace(/\s+/g, "")), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", src(der), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/// L'intestazione Authorization: dice al servizio push chi spedisce (RFC 8292).
export async function vapidAuthorization(endpoint: string, vapid: Vapid, now = Date.now()): Promise<string> {
  const part = (o: unknown) => b64url(te.encode(JSON.stringify(o)));
  const unsigned = `${part({ typ: "JWT", alg: "ES256" })}.${part({
    aud: new URL(endpoint).origin,
    exp: Math.floor(now / 1000) + 12 * 3600,
    sub: vapid.subject,
  })}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, vapid.privateKey, src(te.encode(unsigned))),
  );
  return `vapid t=${unsigned}.${b64url(signature)}, k=${vapid.publicKey}`;
}

/// Spedisce [payload] (testo JSON) al browser dell'iscrizione. La risposta 404 o 410 dice che
/// l'iscrizione non esiste più.
export async function sendWebPush(
  sub: WebPushSubscription,
  payload: string,
  vapid: Vapid,
  opts: { ttl?: number; send?: typeof fetch } = {},
): Promise<Response> {
  const body = await encrypt(sub, te.encode(payload));
  return (opts.send ?? fetch)(sub.endpoint, {
    method: "POST",
    headers: {
      Authorization: await vapidAuthorization(sub.endpoint, vapid),
      "Content-Encoding": "aes128gcm",
      "Content-Type": "application/octet-stream",
      // Se il computer è spento il messaggio aspetta al massimo mezza giornata.
      TTL: String(opts.ttl ?? 12 * 3600),
      Urgency: "high",
    },
    body: src(body),
  });
}
