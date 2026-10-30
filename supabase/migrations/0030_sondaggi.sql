-- Sondaggi in chat (ottobre 2026). Un sondaggio è un messaggio: la domanda nel testo, le
-- opzioni nel meta.
--   meta = {"type": "poll", "options": ["Martedì", "Mercoledì"], "multiple": false}
-- Da 2 a 10 opzioni diverse (da 1 a 80 caratteri), domanda fino a 300 caratteri, niente
-- allegati. Si vota con vote_poll (una riga per chi vota, con le opzioni scelte: cambiando
-- idea la riga si aggiorna, così il tempo reale filtrato per sondaggio la riceve sempre);
-- chi l'ha creato o il Direttivo lo chiude con close_poll (meta.closed_at). I voti li vede
-- chi vede il canale.

create or replace function public.valid_poll_meta(m jsonb) returns boolean
language sql immutable set search_path = public as $$
  select case
    when jsonb_typeof(m) <> 'object' then false
    when coalesce(jsonb_typeof(m->'options'), '') <> 'array' then false
    when jsonb_array_length(m->'options') not between 2 and 10 then false
    when coalesce(jsonb_typeof(m->'multiple'), 'boolean') <> 'boolean' then false
    when exists (
      select 1 from jsonb_array_elements(m->'options') o
      where jsonb_typeof(o) <> 'string'
         or char_length(btrim(o #>> '{}')) not between 1 and 80) then false
    else (select count(distinct lower(btrim(o #>> '{}')))
          from jsonb_array_elements(m->'options') o) = jsonb_array_length(m->'options')
  end
$$;

alter table public.messages drop constraint if exists messages_poll_valid;
alter table public.messages add constraint messages_poll_valid check (
  meta is null or meta->>'type' is distinct from 'poll'
  or (kind = 'user'
      and char_length(btrim(coalesce(body, ''))) between 1 and 300
      and image_path is null and audio_path is null and replay_path is null
      and public.valid_poll_meta(meta))
);

-- Un sondaggio nasce aperto: la chiusura la scrive solo close_poll.
create or replace function public.messages_poll_before_insert() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.meta->>'type' = 'poll' then new.meta := new.meta - 'closed_at'; end if;
  return new;
end $$;
drop trigger if exists messages_poll_before_insert on public.messages;
create trigger messages_poll_before_insert before insert on public.messages
  for each row execute function public.messages_poll_before_insert();

create table if not exists public.poll_votes (
  message_id uuid not null references public.messages on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  -- Le opzioni scelte (indici in meta.options); vuoto = voto ritirato.
  options smallint[] not null default '{}',
  voted_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create index if not exists poll_votes_user_idx on public.poll_votes (user_id);

alter table public.poll_votes enable row level security;
drop policy if exists "lettura chi vede il canale" on public.poll_votes;
create policy "lettura chi vede il canale" on public.poll_votes for select
  using (exists (select 1 from messages m
                 where m.id = message_id and can_see_channel(m.channel_id)));
-- Nessuna scrittura diretta: si passa da vote_poll.

-- Vota [p_options] (vuoto: ritira il voto) al posto delle scelte di prima. Una sola
-- opzione se il sondaggio non è a scelta multipla; niente voti a sondaggio chiuso.
create or replace function public.vote_poll(p_message uuid, p_options int[])
returns void language plpgsql security definer set search_path = public as $$
declare
  m record;
  n int;
  picked smallint[];
begin
  -- Il messaggio resta fermo finché il voto è scritto: una chiusura nello stesso
  -- momento arriva prima o dopo, mai in mezzo.
  select id, channel_id, meta into m from messages where id = p_message for update;
  if not found or m.meta->>'type' is distinct from 'poll' or auth.uid() is null
     or not can_see_channel(m.channel_id) then
    raise exception 'Sondaggio non trovato';
  end if;
  if m.meta ? 'closed_at' then
    raise exception 'Il sondaggio è chiuso';
  end if;
  n := jsonb_array_length(m.meta->'options');
  if exists (select 1 from unnest(coalesce(p_options, '{}')) x where x is null or x < 0 or x >= n) then
    raise exception 'Opzione non valida';
  end if;
  picked := array(select distinct x::smallint from unnest(coalesce(p_options, '{}')) x order by 1);
  if cardinality(picked) > 1 and not coalesce((m.meta->>'multiple')::boolean, false) then
    raise exception 'In questo sondaggio si sceglie una sola opzione';
  end if;
  insert into poll_votes (message_id, user_id, options, voted_at)
  values (p_message, auth.uid(), picked, now())
  on conflict (message_id, user_id)
    do update set options = excluded.options, voted_at = excluded.voted_at;
end $$;
revoke all on function public.vote_poll(uuid, int[]) from public, anon;
grant execute on function public.vote_poll(uuid, int[]) to authenticated;

-- Chiude il sondaggio: chi l'ha creato o il Direttivo. Restituisce il meta aggiornato.
create or replace function public.close_poll(p_message uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m record;
  closed jsonb;
begin
  select id, channel_id, author_id, meta into m from messages where id = p_message for update;
  if not found or m.meta->>'type' is distinct from 'poll' or auth.uid() is null
     or not can_see_channel(m.channel_id) then
    raise exception 'Sondaggio non trovato';
  end if;
  if m.author_id is distinct from auth.uid() and not is_direttivo() then
    raise exception 'Il sondaggio lo chiude solo chi l''ha creato o il Direttivo';
  end if;
  if m.meta ? 'closed_at' then return m.meta; end if;
  update messages set meta = meta || jsonb_build_object('closed_at', app_now())
  where id = p_message
  returning meta into closed;
  return closed;
end $$;
revoke all on function public.close_poll(uuid) from public, anon;
grant execute on function public.close_poll(uuid) to authenticated;

-- I voti in tempo reale nell'app.
do $$ begin
  alter publication supabase_realtime add table public.poll_votes;
exception when duplicate_object then null;
end $$;
