// Funzione "voice-token": il biglietto d'ingresso (token Agora) per la stanza vocale.
// L'app la chiama con il JWT dell'utente: { room: "<id della stanza>" }.
// Risponde { appId, token, channel, uid, expiresAt } (il canale Agora è l'id della stanza).
//
// Variabili (impostate dal workflow "Funzioni"):
//   AGORA_APP_ID, AGORA_APP_CERTIFICATE (senza: 503 "voce non configurata")
//   SUPABASE_URL, SUPABASE_ANON_KEY (fornite da Supabase)

import { createClient } from "npm:@supabase/supabase-js@2";
import { RtcRole, RtcTokenBuilder } from "npm:agora-token@2.0.5";

/// Il token vale un'ora: l'app ne chiede uno nuovo poco prima della scadenza
/// (senza uscire dalla stanza), e un biglietto finito in mani sbagliate scade presto.
const TOKEN_SECONDS = 3600;

/// Numero utente Agora ricavato dall'id del profilo: lo stesso calcolo dell'app
/// (agoraUidFor) e del database (agora_uid_for).
function agoraUidFor(userId: string): number {
  let h = 0;
  for (let i = 0; i < userId.length; i++) {
    h = (h * 31 + userId.charCodeAt(i)) & 0x7fffffff;
  }
  return h === 0 ? 1 : h;
}

Deno.serve(async (req) => {
  const appId = Deno.env.get("AGORA_APP_ID");
  const certificate = Deno.env.get("AGORA_APP_CERTIFICATE");
  if (!appId || !certificate) {
    return Response.json({ error: "voce non configurata" }, { status: 503 });
  }
  const authorization = req.headers.get("Authorization") ?? "";
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );
  const { data: { user } } = await db.auth.getUser();
  if (!user) return Response.json({ error: "non autenticato" }, { status: 401 });

  let room = "";
  try {
    room = String((await req.json()).room ?? "");
  } catch {
    room = "";
  }
  if (!/^[0-9a-f-]{36}$/.test(room)) {
    return Response.json({ error: "stanza non valida" }, { status: 400 });
  }
  // La stanza deve esistere, essere aperta e visibile all'utente (RLS con il suo JWT).
  const { data: r } = await db
    .from("voice_rooms").select("id, closed_at").eq("id", room).maybeSingle();
  if (!r || r.closed_at) {
    return Response.json({ error: "stanza chiusa" }, { status: 404 });
  }
  // Solo chi è entrato (sessione aperta) riceve il biglietto: niente ascolti invisibili,
  // e chi è stato fatto uscire per assenza di segnale non rinnova più.
  const { data: s } = await db
    .from("voice_sessions").select("id")
    .eq("room_id", room).eq("user_id", user.id).is("left_at", null).maybeSingle();
  if (!s) {
    return Response.json({ error: "non sei nella stanza" }, { status: 409 });
  }
  // Il biglietto vale solo per il numero utente di chi lo chiede: nessuno può
  // entrare con il nome di un altro.
  const uid = agoraUidFor(user.id);
  const token = RtcTokenBuilder.buildTokenWithUid(
    appId, certificate, room, uid, RtcRole.PUBLISHER, TOKEN_SECONDS, TOKEN_SECONDS,
  );
  const expiresAt = Math.floor(Date.now() / 1000) + TOKEN_SECONDS;
  return Response.json({ appId, token, channel: room, uid, expiresAt });
});
