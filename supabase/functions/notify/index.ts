// Funzione "notify": invia notifiche push personali tramite Firebase Cloud Messaging.
// Viene chiamata dal database (trigger, pg_cron + pg_net) con l'intestazione x-milanac-secret.
//
// Eventi gestiti:
//   { kind: "formation", id }               → ai membri della squadra: titolare (con ruolo) o panchina
//   { kind: "chat_message", id }            → ai membri del canale, escluso l'autore e chi l'ha silenziato
//   { kind: "match_result", id }            → ai giocatori della squadra: risultato e marcatori
//   { kind: "rules", version }              → a tutti i membri: nuova versione del regolamento da accettare
//   { kind: "event", id }                   → alla squadra (o a tutti): nuovo appuntamento in calendario
//   { kind: "attendance_reminder", users }  → alle 18:00 a chi non ha ancora risposto per stasera
//   { kind: "attendance_auto_absent", users } → alle 18:30 a chi è risultato assente senza rispondere
//   { kind: "video_proposed", id }          → al Direttivo: un giocatore propone un video
//   { kind: "video_published", id }         → a chi l'ha proposto: il video è stato pubblicato
//   { kind: "news", id }                    → aggiornamento FC 27 (a tutti) o di una console (per piattaforma)
//   { kind: "special_card", id }            → al giocatore: ha ricevuto una carta nero/oro o blu elettrico
//   { kind: "special_cards_week", match }   → alla squadra: le carte speciali della giornata
//   { kind: "cleanup" }                     → nessuna notifica: rimuove dallo Storage i file in coda
//                                             (allegati della chat scaduti o eliminati)
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
  const { kind, id, version, users, match } = await req.json();
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  if (kind === "cleanup") return Response.json({ removed: await cleanupStorage(db) });

  let pushes: Push[] = [];
  if (kind === "formation") pushes = await formationPushes(db, id);
  else if (kind === "chat_message") pushes = await chatPushes(db, id);
  else if (kind === "match_result") pushes = await matchResultPushes(db, id);
  else if (kind === "rules") pushes = await rulesPushes(db, version);
  else if (kind === "event") pushes = await eventPushes(db, id);
  else if (kind === "attendance_reminder") pushes = attendancePushes(users, "reminder");
  else if (kind === "attendance_auto_absent") pushes = attendancePushes(users, "absent");
  else if (kind === "video_proposed") pushes = await videoProposedPushes(db, id);
  else if (kind === "video_published") pushes = await videoPublishedPushes(db, id);
  else if (kind === "news") pushes = await newsPushes(db, id);
  else if (kind === "special_card") pushes = await specialCardPushes(db, id);
  else if (kind === "special_cards_week") pushes = await specialCardsWeekPushes(db, match);
  else return new Response("unknown kind", { status: 400 });

  const account = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!account) {
    return Response.json({ skipped: "firebase non configurato", pushes: pushes.length });
  }
  const sent = await sendAll(db, JSON.parse(account), pushes);
  return Response.json({ pushes: pushes.length, sent });
});

const TEAM_NAMES: Record<string, string> = { milanac: "Milan AC", futuro: "Milan AC Futuro" };
const PLATFORM_NAMES: Record<string, string> = { ps5: "PlayStation", xbox: "Xbox" };

/// Membri attivi del club (chi ha finito la registrazione), eventualmente di una squadra.
async function members(db: SupabaseClient, team?: string | null): Promise<{ id: string }[]> {
  let q = db.from("profiles").select("id").eq("active", true).neq("club_role", "pending");
  if (team) q = q.contains("teams", [team]);
  const { data } = await q;
  return data ?? [];
}

/// "Sabato 11 ott, 21:30" in ora italiana.
function whenRome(iso: string): string {
  const s = new Intl.DateTimeFormat("it-IT", {
    timeZone: "Europe/Rome", weekday: "long", day: "numeric", month: "short",
    hour: "2-digit", minute: "2-digit",
  }).format(new Date(iso)).replace(/\.|,/g, "");
  // "sabato 11 ott 21:30" → "Sabato 11 ott, 21:30"
  const parts = s.split(" ");
  const time = parts.pop();
  return `${parts.join(" ")}, ${time}`.replace(/^./, (c) => c.toUpperCase());
}

/// Giorno (AAAA-MM-GG) in ora italiana.
function dayRome(iso: string): string {
  const p = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Rome", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(new Date(iso));
  return p;
}

// ------------------------------------------------------------------ formazione

async function formationPushes(db: SupabaseClient, formationId: string): Promise<Push[]> {
  const { data: formation } = await db
    .from("formations").select("team").eq("id", formationId).single();
  const team = formation?.team ?? "milanac";
  const teamName = TEAM_NAMES[team] ?? "Milan AC";
  const { data: slots } = await db
    .from("formation_slots").select("label, player_id").eq("formation_id", formationId);
  // Solo i giocatori di quella squadra (chi è in entrambe riceve entrambe le formazioni).
  const starters = new Map((slots ?? []).filter((s) => s.player_id).map((s) => [s.player_id, s.label]));
  return (await members(db, team)).map((m) => {
    const role = starters.get(m.id);
    return {
      userId: m.id,
      title: `📋 ${teamName}: formazione pubblicata`,
      body: role ? `Sei titolare: ${role}. Forza ${teamName}!` : "Parti dalla panchina: tieniti pronto!",
      route: "/formazione",
      data: { team },
    };
  });
}

// ------------------------------------------------------------------ risultato

async function matchResultPushes(db: SupabaseClient, matchId: string): Promise<Push[]> {
  const { data: match } = await db
    .from("matches").select("id, team, opponent, home, goals_for, goals_against").eq("id", matchId).single();
  if (!match || match.goals_for == null || match.goals_against == null) return [];
  const team = match.team ?? "milanac";
  const us = TEAM_NAMES[team] ?? "Milan AC";
  const score = match.home
    ? `${us} ${match.goals_for}–${match.goals_against} ${match.opponent}`
    : `${match.opponent} ${match.goals_against}–${match.goals_for} ${us}`;
  return (await members(db, team)).map((m) => ({
    userId: m.id,
    title: `⚽ ${score}`,
    body: "Risultato registrato: guarda marcatori e highlights.",
    route: `/partita/${match.id}`,
    data: { match: match.id },
  }));
}

// ------------------------------------------------------------------ regolamento

async function rulesPushes(db: SupabaseClient, version: number | undefined): Promise<Push[]> {
  const label = version ? `Versione ${version}` : "Nuova versione";
  return (await members(db)).map((m) => ({
    userId: m.id,
    title: "📜 Nuovo regolamento del club",
    body: `${label}: al prossimo accesso leggilo e accettalo per continuare.`,
    route: "/regolamento",
  }));
}

// ------------------------------------------------------------------ eventi

async function eventPushes(db: SupabaseClient, eventId: string): Promise<Push[]> {
  const { data: e } = await db
    .from("events").select("id, type, title, starts_at, team, location").eq("id", eventId).single();
  if (!e) return [];
  const teamName = e.team ? TEAM_NAMES[e.team] ?? "Milan AC" : "tutto il club";
  const kind = ({ torneo: "Partita ufficiale", amichevole: "Amichevole", allenamento: "Allenamento",
    riunione: "Riunione" } as Record<string, string>)[e.type] ?? "Evento";
  const day = dayRome(e.starts_at);
  return (await members(db, e.team)).map((m) => ({
    userId: m.id,
    title: `📅 ${kind} · ${teamName}`,
    body: `${whenRome(e.starts_at)}: ${e.title}${e.location ? ` · ${e.location}` : ""}`,
    route: e.type === "riunione" ? "/calendario" : `/presenze?giorno=${day}`,
    data: { event: e.id, day },
  }));
}

// ------------------------------------------------------------------ presenze (18:00 e 18:30)

function attendancePushes(users: unknown, what: "reminder" | "absent"): Push[] {
  const ids = Array.isArray(users) ? users.filter((u) => typeof u === "string") as string[] : [];
  return ids.map((userId) => what === "reminder"
    ? {
      userId,
      title: "⚽ Ci sei stasera?",
      body: "Rispondi entro le 18:30: presente, in ritardo o assente.",
      route: "/presenze",
    }
    : {
      userId,
      title: "Stasera risulti assente",
      body: "Non hai risposto entro le 18:30. Se è un errore, avvisa il Direttivo.",
      route: "/presenze",
    });
}

// ------------------------------------------------------------------ Mondo Proclub

async function videoProposedPushes(db: SupabaseClient, linkId: string): Promise<Push[]> {
  const { data: v } = await db
    .from("shared_links").select("id, title, profiles(display_name)").eq("id", linkId).single();
  if (!v) return [];
  // deno-lint-ignore no-explicit-any
  const author = (v as any).profiles?.display_name ?? "Un giocatore";
  const { data: direttivo } = await db
    .from("profiles").select("id").eq("active", true).eq("club_role", "direttivo");
  return (direttivo ?? []).map((m) => ({
    userId: m.id,
    title: "🎬 Video proposto per Mondo Proclub",
    body: `${author} propone: ${v.title}`,
    route: "/mondo",
    data: { video: v.id },
  }));
}

async function videoPublishedPushes(db: SupabaseClient, linkId: string): Promise<Push[]> {
  const { data: v } = await db
    .from("shared_links").select("id, title, created_by, published_by").eq("id", linkId).single();
  if (!v || !v.created_by || v.created_by === v.published_by) return [];
  return [{
    userId: v.created_by,
    title: "🎬 Il tuo video è stato pubblicato",
    body: `${v.title} è ora in Mondo Proclub.`,
    route: "/mondo",
    data: { video: v.id },
  }];
}

// ------------------------------------------------------------------ notizie

async function newsPushes(db: SupabaseClient, newsId: number): Promise<Push[]> {
  const { data: n } = await db
    .from("news").select("id, title, category, platform").eq("id", newsId).single();
  if (!n) return [];
  if (n.category === "aggiornamenti") {
    return (await members(db)).map((m) => ({
      userId: m.id,
      title: "🔄 Nuovo aggiornamento FC 27",
      body: `${n.title} — aggiorna il gioco prima del match!`,
      route: "/mondo?scheda=notizie",
    }));
  }
  if (n.category === "console" && n.platform) {
    const { data: owners } = await db
      .from("profiles").select("id").eq("active", true).neq("club_role", "pending")
      .eq("platform", n.platform);
    return (owners ?? []).map((m) => ({
      userId: m.id,
      title: `🎮 Aggiornamento ${PLATFORM_NAMES[n.platform] ?? n.platform}`,
      body: n.title,
      route: "/mondo?scheda=notizie",
    }));
  }
  return [];
}

// ------------------------------------------------------------------ chat

async function chatPushes(db: SupabaseClient, messageId: string): Promise<Push[]> {
  const { data: msg } = await db
    .from("messages")
    .select("id, kind, body, image_path, audio_path, meta, author_id, channel_id, channels(name, slug, team, direttivo_only), profiles(display_name)")
    .eq("id", messageId).single();
  if (!msg) return [];
  // deno-lint-ignore no-explicit-any
  const channel = (msg as any).channels;
  // deno-lint-ignore no-explicit-any
  const author = (msg as any).profiles?.display_name ?? "MILANAC";
  // I canali riservati (Sala Direttivo) notificano solo il Direttivo; quelli di squadra solo la squadra.
  let membersQuery = db.from("profiles").select("id").eq("active", true);
  if (channel?.direttivo_only) membersQuery = membersQuery.eq("club_role", "direttivo");
  else {
    membersQuery = membersQuery.neq("club_role", "pending");
    if (channel?.team) membersQuery = membersQuery.contains("teams", [channel.team]);
  }
  const { data: members } = await membersQuery;
  const { data: mutes } = await db
    .from("channel_mutes").select("user_id").eq("channel_id", msg.channel_id);
  const muted = new Set((mutes ?? []).map((m) => m.user_id));
  const text = msg.body?.trim() || (msg.image_path ? "📷 Foto" : msg.audio_path ? "🎤 Messaggio vocale" : "");
  return (members ?? [])
    .filter((m) => m.id !== msg.author_id && !muted.has(m.id))
    .map((m) => ({
      userId: m.id,
      // I messaggi automatici contengono già il nome.
      title: msg.meta?.type === "announcement"
        ? `📣 Avviso del Direttivo · ${author}`
        : msg.kind === "system" ? `#${channel?.name ?? "chat"}` : `#${channel?.name ?? "chat"} · ${author}`,
      body: text.length > 140 ? text.slice(0, 137) + "…" : text,
      route: `/chat/${channel?.slug ?? ""}`,
      data: { channel: channel?.slug ?? "" },
    }));
}

// ------------------------------------------------------------------ carte speciali

const REPARTO_NAMES: Record<string, string> = {
  POR: "portiere", DIF: "difensore", CEN: "centrocampista", ATT: "attaccante",
};

async function specialCardPushes(db: SupabaseClient, cardId: string): Promise<Push[]> {
  const { data: c } = await db
    .from("special_cards").select("id, player_id, kind, reparto, bonus, reason").eq("id", cardId).single();
  if (!c) return [];
  const bonus = `+${c.bonus}`;
  return [c.kind === "blu"
    ? {
      userId: c.player_id,
      title: "⚡ Carta blu elettrico!",
      body: `${c.reason ?? "Prestazione da ricordare"}: la tua carta è blu elettrico (${bonus}) per una settimana.`,
      route: "/carta",
      data: { card: c.id },
    }
    : {
      userId: c.player_id,
      title: "🏅 Carta nero/oro della settimana",
      body: `Hai ricevuto la carta nero/oro della settimana (${bonus}) come ${REPARTO_NAMES[c.reparto] ?? c.reparto}. Vale 7 giorni!`,
      route: "/carta",
      data: { card: c.id },
    }];
}

async function specialCardsWeekPushes(db: SupabaseClient, matchId: string): Promise<Push[]> {
  const { data: m } = await db.from("matches").select("id, team").eq("id", matchId).single();
  if (!m) return [];
  const { data: msg } = await db
    .from("messages").select("body").eq("kind", "system")
    .eq("meta->>type", "special_cards").eq("meta->>match", matchId).maybeSingle();
  // "Carte speciali della 3ª giornata (Milan AC 3–1 Rivali): POR Rossi +5, …"
  const body = msg?.body ?? "Guarda chi ha la carta speciale di questa settimana.";
  const title = body.match(/^Carte speciali ([^(]+)/)?.[1]?.trim();
  return (await members(db, m.team)).map((u) => ({
    userId: u.id,
    title: `🏅 Carte speciali ${title ?? "della giornata"}`,
    body: body.replace(/^Carte speciali [^:]*: /, ""),
    route: "/carte-speciali",
    data: { match: m.id },
  }));
}

// ------------------------------------------------------------------ pulizia dello Storage

/// Rimuove i file in coda (storage_cleanup); le righe restano se la rimozione fallisce.
async function cleanupStorage(db: SupabaseClient): Promise<number> {
  const { data: rows } = await db.from("storage_cleanup").select("bucket, path").limit(500);
  let removed = 0;
  for (const bucket of new Set((rows ?? []).map((r) => r.bucket))) {
    const paths = (rows ?? []).filter((r) => r.bucket === bucket).map((r) => r.path);
    const { error } = await db.storage.from(bucket).remove(paths);
    if (error) continue;
    await db.from("storage_cleanup").delete().eq("bucket", bucket).in("path", paths);
    removed += paths.length;
  }
  return removed;
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
              android: { priority: "high", notification: { color: "#C61C23" } },
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
