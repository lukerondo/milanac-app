// Funzione "notify": invia notifiche push personali tramite Firebase Cloud Messaging.
// Viene chiamata dal database (trigger + pg_net) con l'intestazione x-milanac-secret.
//
// Eventi gestiti:
//   { kind: "formation", id }     → ai membri della squadra: titolare (con ruolo) o panchina
//   { kind: "chat_message", id }  → ai membri del canale, escluso l'autore e chi l'ha silenziato
//
// Variabili (impostate dal workflow "Funzioni"):
//   WEBHOOK_SECRET, FIREBASE_SERVICE_ACCOUNT (JSON; se manca le notifiche sono disattivate)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (fornite automaticamente da Supabase)

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

type Push = { userId: string; title: string; body: string; route: string; data?: Record<string, string> };

Deno.serve(async (req) => {
  if (req.headers.get("x-milanac-secret") !== Deno.env.get("WEBHOOK_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }
  const { kind, id } = await req.json();
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  let pushes: Push[] = [];
  if (kind === "formation") pushes = await formationPushes(db, id);
  else if (kind === "chat_message") pushes = await chatPushes(db, id);
  else return new Response("unknown kind", { status: 400 });

  const account = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!account) {
    return Response.json({ skipped: "firebase non configurato", pushes: pushes.length });
  }
  const sent = await sendAll(db, JSON.parse(account), pushes);
  return Response.json({ pushes: pushes.length, sent });
});

// ------------------------------------------------------------------ formazione

async function formationPushes(db: SupabaseClient, formationId: string): Promise<Push[]> {
  const { data: formation } = await db
    .from("formations").select("team").eq("id", formationId).single();
  const team = formation?.team ?? "milanac";
  const teamName = TEAM_NAMES[team] ?? "MILANAC";
  const { data: slots } = await db
    .from("formation_slots").select("label, player_id").eq("formation_id", formationId);
  // Solo i giocatori di quella squadra (chi è in entrambe riceve entrambe le formazioni).
  const { data: members } = await db
    .from("profiles").select("id").eq("active", true).neq("club_role", "pending")
    .contains("teams", [team]);
  const starters = new Map((slots ?? []).filter((s) => s.player_id).map((s) => [s.player_id, s.label]));
  return (members ?? []).map((m) => {
    const role = starters.get(m.id);
    return {
      userId: m.id,
      title: `📋 ${teamName}: formazione pubblicata`,
      body: role ? `Stasera giochi ${role} titolare. Forza ${teamName}!` : "Stasera parti dalla panchina: tieniti pronto!",
      route: "/formazione",
      data: { team },
    };
  });
}

const TEAM_NAMES: Record<string, string> = { milanac: "MILANAC", futuro: "MILANAC FUTURO" };

// ------------------------------------------------------------------ chat

async function chatPushes(db: SupabaseClient, messageId: string): Promise<Push[]> {
  const { data: msg } = await db
    .from("messages")
    .select("id, kind, body, image_path, meta, author_id, channel_id, channels(name, slug, direttivo_only), profiles(display_name)")
    .eq("id", messageId).single();
  if (!msg) return [];
  // deno-lint-ignore no-explicit-any
  const channel = (msg as any).channels;
  // deno-lint-ignore no-explicit-any
  const author = (msg as any).profiles?.display_name ?? "MILANAC";
  // I canali riservati (Sala Direttivo) notificano solo il Direttivo.
  const membersQuery = db.from("profiles").select("id").eq("active", true);
  const { data: members } = channel?.direttivo_only
    ? await membersQuery.eq("club_role", "direttivo")
    : await membersQuery.neq("club_role", "pending");
  const { data: mutes } = await db
    .from("channel_mutes").select("user_id").eq("channel_id", msg.channel_id);
  const muted = new Set((mutes ?? []).map((m) => m.user_id));
  const text = msg.body?.trim() || (msg.image_path ? "📷 Foto" : "");
  return (members ?? [])
    .filter((m) => m.id !== msg.author_id && !muted.has(m.id))
    .map((m) => ({
      userId: m.id,
      // I messaggi automatici (ritardi, assenze) contengono già il nome.
      title: msg.meta?.type === "announcement"
        ? `📣 Avviso del Direttivo · ${author}`
        : msg.kind === "system" ? `#${channel?.name ?? "chat"}` : `#${channel?.name ?? "chat"} · ${author}`,
      body: text.length > 140 ? text.slice(0, 137) + "…" : text,
      route: `/chat/${channel?.slug ?? ""}`,
      data: { channel: channel?.slug ?? "" },
    }));
}

// ------------------------------------------------------------------ FCM

async function sendAll(db: SupabaseClient, account: ServiceAccount, pushes: Push[]): Promise<number> {
  if (pushes.length === 0) return 0;
  const { data: tokens } = await db
    .from("device_tokens").select("token, user_id").in("user_id", pushes.map((p) => p.userId));
  const accessToken = await googleAccessToken(account);
  let sent = 0;
  for (const p of pushes) {
    for (const t of (tokens ?? []).filter((t) => t.user_id === p.userId)) {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            message: {
              token: t.token,
              notification: { title: p.title, body: p.body },
              data: { route: p.route, ...(p.data ?? {}) },
              android: { priority: "high", notification: { color: "#C8102E" } },
              apns: { payload: { aps: { sound: "default" } } },
            },
          }),
        },
      );
      if (res.ok) sent++;
      else if (res.status === 404 || res.status === 400) {
        // Token scaduto o non valido: lo rimuoviamo.
        await db.from("device_tokens").delete().eq("token", t.token);
      }
    }
  }
  return sent;
}

type ServiceAccount = { client_email: string; private_key: string; project_id: string };

async function googleAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const enc = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  const unsigned = `${enc({ alg: "RS256", typ: "JWT" })}.${enc({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })}`;
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const jwt = `${unsigned}.${btoa(String.fromCharCode(...sig)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_")}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`OAuth Google fallito: ${JSON.stringify(json)}`);
  return json.access_token;
}
