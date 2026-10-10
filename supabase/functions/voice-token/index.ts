// Funzione "voice-token": il biglietto d'ingresso (token Agora) per la stanza vocale.
// L'app la chiama con il JWT dell'utente: { room: "<id della stanza>" }.
// Risponde { appId, token, channel, expiresAt } (il canale Agora è l'id della stanza).
//
// Variabili (impostate dal workflow "Funzioni"):
//   AGORA_APP_ID, AGORA_APP_CERTIFICATE (senza: 503 "voce non configurata")
//   SUPABASE_URL, SUPABASE_ANON_KEY (fornite da Supabase)

import { createClient } from "npm:@supabase/supabase-js@2";
import { RtcRole, RtcTokenBuilder } from "npm:agora-token@2.0.5";

/// Il token vale 3 ore: basta per un briefing, e una stanza abbandonata non resta aperta.
const TOKEN_SECONDS = 3 * 3600;

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
  // uid 0: Agora assegna l'identificativo all'ingresso (l'app lo salva nella sessione).
  const token = RtcTokenBuilder.buildTokenWithUid(
    appId, certificate, room, 0, RtcRole.PUBLISHER, TOKEN_SECONDS, TOKEN_SECONDS,
  );
  const expiresAt = Math.floor(Date.now() / 1000) + TOKEN_SECONDS;
  return Response.json({ appId, token, channel: room, expiresAt });
});
