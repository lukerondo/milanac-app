// Prove di webpush.ts: deno test supabase/functions/notify/
import {
  allowedEndpoint,
  b64url,
  encrypt,
  fromB64url,
  importVapidPrivateKey,
  MAX_PAYLOAD,
  sendWebPush,
  vapidAuthorization,
  webPayload,
} from "./webpush.ts";

function equal(actual: unknown, expected: unknown, what: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${what}: atteso ${JSON.stringify(expected)}, trovato ${JSON.stringify(actual)}`);
  }
}

// Vettori dell'appendice A dell'RFC 8291.
const RFC = {
  plaintext: "When I grow up, I want to be a watermelon",
  p256dh: "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
  auth: "BTBZMqHH6r4Tts7J_aSIgg",
  salt: "DGv6ra1nlYgDCS1FRnbzlw",
  localPublic: "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8",
  localPrivate: "yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw",
  body:
    "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN",
};

async function rfcLocalKeys(): Promise<CryptoKeyPair> {
  const point = fromB64url(RFC.localPublic);
  const jwk = {
    kty: "EC",
    crv: "P-256",
    x: b64url(point.slice(1, 33)),
    y: b64url(point.slice(33, 65)),
  };
  const algorithm = { name: "ECDH", namedCurve: "P-256" };
  return {
    privateKey: await crypto.subtle.importKey("jwk", { ...jwk, d: RFC.localPrivate }, algorithm, true, ["deriveBits"]),
    publicKey: await crypto.subtle.importKey("jwk", jwk, algorithm, true, []),
  };
}

Deno.test("cifratura: il vettore dell'RFC 8291", async () => {
  const body = await encrypt(
    { p256dh: RFC.p256dh, auth: RFC.auth },
    new TextEncoder().encode(RFC.plaintext),
    { salt: fromB64url(RFC.salt), localKeys: await rfcLocalKeys() },
  );
  equal(b64url(body), RFC.body, "corpo cifrato");
});

Deno.test("cifratura: sale e chiavi casuali, limiti e iscrizioni non valide", async () => {
  const sub = { p256dh: RFC.p256dh, auth: RFC.auth };
  const text = new TextEncoder().encode("ciao");
  const a = await encrypt(sub, text), b = await encrypt(sub, text);
  // Intestazione (16 + 4 + 1 + 65) + testo + chiusura + autenticazione.
  equal(a.length, 86 + 4 + 1 + 16, "lunghezza");
  if (b64url(a) === b64url(b)) throw new Error("due messaggi uguali devono uscire diversi");
  await encrypt(sub, new Uint8Array(MAX_PAYLOAD));
  for (const bad of [
    () => encrypt(sub, new Uint8Array(MAX_PAYLOAD + 1)),
    () => encrypt({ p256dh: "AAAA", auth: RFC.auth }, text),
    () => encrypt({ p256dh: RFC.p256dh, auth: "AAAA" }, text),
  ]) {
    let failed = false;
    try {
      await bad();
    } catch (_) {
      failed = true;
    }
    if (!failed) throw new Error("doveva essere rifiutato");
  }
});

Deno.test("solo i servizi push dei browser", () => {
  for (const ok of [
    "https://fcm.googleapis.com/fcm/send/abc",
    "https://updates.push.services.mozilla.com/wpush/v2/abc",
    "https://wns2-par02p.notify.windows.com/w/?token=abc",
    "https://web.push.apple.com/abc",
  ]) equal(allowedEndpoint(ok), true, ok);
  for (const no of [
    "http://fcm.googleapis.com/fcm/send/abc",
    "https://example.com/push",
    "https://fcm.googleapis.com.example.com/x",
    "https://evilgoogleapis.com/x",
    "https://10.0.0.1/x",
    "non un indirizzo",
  ]) equal(allowedEndpoint(no), false, no);
});

Deno.test("firma VAPID e richiesta al servizio push", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const publicKey = b64url(new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)));
  const vapid = {
    publicKey,
    privateKey: await importVapidPrivateKey(btoa(String.fromCharCode(...pkcs8))),
    subject: "https://milanacproclub.vercel.app",
  };
  const endpoint = "https://fcm.googleapis.com/fcm/send/abc";
  const now = Date.UTC(2026, 10, 10);
  const header = await vapidAuthorization(endpoint, vapid, now);
  const match = /^vapid t=([\w-]+)\.([\w-]+)\.([\w-]+), k=([\w-]+)$/.exec(header);
  if (!match) throw new Error(`intestazione inattesa: ${header}`);
  const claims = JSON.parse(new TextDecoder().decode(fromB64url(match[2])));
  equal(claims, {
    aud: "https://fcm.googleapis.com",
    exp: now / 1000 + 12 * 3600,
    sub: "https://milanacproclub.vercel.app",
  }, "contenuto del gettone");
  equal(match[4], publicKey, "chiave pubblica");
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pair.publicKey,
    fromB64url(match[3]) as unknown as BufferSource,
    new TextEncoder().encode(`${match[1]}.${match[2]}`),
  );
  equal(valid, true, "firma");

  let request: Request | undefined;
  const res = await sendWebPush(
    { endpoint, p256dh: RFC.p256dh, auth: RFC.auth },
    JSON.stringify({ title: "Prova" }),
    vapid,
    { send: (input, init) => {
      request = new Request(input as string, init);
      return Promise.resolve(new Response(null, { status: 201 }));
    } },
  );
  equal(res.status, 201, "risposta");
  equal(request!.method, "POST", "metodo");
  equal(request!.headers.get("content-encoding"), "aes128gcm", "codifica");
  equal(request!.headers.get("ttl"), "43200", "durata");
  equal(request!.headers.get("authorization")!.startsWith("vapid t="), true, "firma nella richiesta");
});

Deno.test("testo della notifica: corto com'è, lungo accorciato, sempre dentro un blocco", () => {
  const short = JSON.parse(webPayload({ title: "Chat", body: "Ciao", route: "/chat/main", data: { channel: "main" } }));
  equal(short, { title: "Chat", body: "Ciao", route: "/chat/main", data: { channel: "main" } }, "corto");
  const long = JSON.parse(webPayload({ title: "Chat", body: "a".repeat(2000), route: "/chat/main" }));
  equal(long.body.length, 280, "accorciato a 280 caratteri");
  equal(long.body.endsWith("…"), true, "con i puntini");
  equal(long.data, {}, "dati vuoti");
  // Emoji e titolo lunghissimo: il corpo si riduce ancora, il messaggio resta nel blocco.
  const heavy = webPayload({ title: "🔥".repeat(700), body: "😀".repeat(280), route: "/" });
  if (new TextEncoder().encode(heavy).length > MAX_PAYLOAD) throw new Error("messaggio troppo lungo");
});
