-- Chat (ottobre 2026): spunte di lettura, reazioni, menzioni e "sta scrivendo".
--  1) Spunte: chi vede un canale vede fin dove l'hanno letto gli altri (channel_reads), in
--     tempo reale; ognuno continua a scrivere solo la propria lettura.
--  2) Reazioni: una per persona e per messaggio, tra poche emoji. Il canale lo mette il
--     database (dal messaggio); toglierla vuol dire svuotarla, così l'app che segue il
--     canale in tempo reale se ne accorge (le eliminazioni non arrivano filtrate).
--  3) Menzioni: nei dati del messaggio (meta.mentions) restano solo membri che vedono il
--     canale, al massimo 20; la funzione notify li avvisa anche se hanno silenziato il canale.
--  4) "Sta scrivendo": messaggi di passaggio sul canale privato "chat:<id del canale>" di
--     Supabase Realtime, permessi solo a chi vede il canale.

-- ---------------------------------------------------------------- 1) spunte
drop policy if exists "letture del canale" on public.channel_reads;
create policy "letture del canale" on public.channel_reads for select
  using (can_see_channel(channel_id));

do $$ begin
  alter publication supabase_realtime add table public.channel_reads;
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------- 2) reazioni
create table if not exists public.message_reactions (
  message_id uuid not null references public.messages on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  channel_id uuid not null references public.channels on delete cascade,
  emoji text check (emoji in ('👍', '❤️', '😂', '😮', '😢', '🔥', '⚽')),  -- null = tolta
  updated_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create index if not exists message_reactions_channel_idx
  on public.message_reactions (channel_id, updated_at desc);

alter table public.message_reactions enable row level security;
drop policy if exists "lettura del canale" on public.message_reactions;
create policy "lettura del canale" on public.message_reactions for select
  using (can_see_channel(channel_id));
drop policy if exists "propria reazione" on public.message_reactions;
create policy "propria reazione" on public.message_reactions for insert
  with check (user_id = auth.uid() and is_member() and can_see_channel(channel_id));
drop policy if exists "propria reazione cambiata" on public.message_reactions;
create policy "propria reazione cambiata" on public.message_reactions for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and is_member() and can_see_channel(channel_id));
drop policy if exists "propria reazione eliminata" on public.message_reactions;
create policy "propria reazione eliminata" on public.message_reactions for delete
  using (user_id = auth.uid());

-- Il canale viene dal messaggio (non da chi reagisce), l'ora è quella del server.
create or replace function public.message_reactions_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.channel_id := (select m.channel_id from messages m where m.id = new.message_id);
  if new.channel_id is null then
    raise exception 'Messaggio non più disponibile';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists message_reactions_before on public.message_reactions;
create trigger message_reactions_before before insert or update on public.message_reactions
  for each row execute function public.message_reactions_before();

do $$ begin
  alter publication supabase_realtime add table public.message_reactions;
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------- 3) menzioni
-- Chi vede un canale, per un utente qualsiasi (stessa regola di can_see_channel). Solo per
-- le funzioni del database: nessuno può chiedere chi vede quale canale.
create or replace function public.member_sees_channel(p_user uuid, p_channel uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from channels c, profiles p
    where c.id = p_channel and p.id = p_user and p.active and p.club_role <> 'pending'
      and (not c.direttivo_only or p.club_role = 'direttivo')
      and (c.team is null or p.club_role = 'direttivo' or c.team = any(p.teams)))
$$;
revoke all on function public.member_sees_channel(uuid, uuid) from public, anon, authenticated;

-- Le menzioni valide: membri (non l'autore) che vedono il canale, senza doppioni, max 20.
create or replace function public.messages_mentions() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  ids uuid[];
begin
  if new.meta is null or not new.meta ? 'mentions' then return new; end if;
  if jsonb_typeof(new.meta->'mentions') = 'array' then
    select array_agg(p.id order by p.id) into ids
    from profiles p
    where p.id::text in (select x #>> '{}' from jsonb_array_elements(new.meta->'mentions') x)
      and p.id is distinct from new.author_id
      and member_sees_channel(p.id, new.channel_id);
  end if;
  if ids is null then
    new.meta := new.meta - 'mentions';
  else
    new.meta := jsonb_set(new.meta, '{mentions}', to_jsonb(ids[1:20]));
  end if;
  return new;
end $$;
drop trigger if exists messages_mentions on public.messages;
create trigger messages_mentions before insert on public.messages
  for each row execute function public.messages_mentions();

-- ---------------------------------------------------------------- 4) "sta scrivendo"
-- L'id del canale della chat dal nome del canale Realtime ("chat:<uuid>"), altrimenti null.
create or replace function public.realtime_chat_channel(p_topic text) returns uuid
language sql immutable set search_path = public as $$
  select case
    when p_topic ~ '^chat:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then substring(p_topic from 6)::uuid
  end
$$;

-- Le regole dei canali privati stanno sulla tabella dei messaggi di Realtime: ci si collega
-- e si scrive (broadcast e presence) solo sul canale di una chat che si vede.
do $$ begin
  if to_regclass('realtime.messages') is null then return; end if;
  execute 'drop policy if exists "chat: ascolta chi vede il canale" on realtime.messages';
  execute $p$
    create policy "chat: ascolta chi vede il canale" on realtime.messages
      for select to authenticated
      using (realtime.messages.extension in ('broadcast', 'presence')
             and public.can_see_channel(public.realtime_chat_channel(realtime.topic())))
  $p$;
  execute 'drop policy if exists "chat: scrive chi vede il canale" on realtime.messages';
  execute $p$
    create policy "chat: scrive chi vede il canale" on realtime.messages
      for insert to authenticated
      with check (realtime.messages.extension in ('broadcast', 'presence')
                  and public.can_see_channel(public.realtime_chat_channel(realtime.topic())))
  $p$;
end $$;
