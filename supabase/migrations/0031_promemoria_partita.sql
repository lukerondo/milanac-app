-- Promemoria partita (ottobre 2026). Per le partite (torneo e amichevole) arrivano da soli
-- due avvisi alla squadra, esclusi gli assenti: un'ora prima ("Tra un'ora si gioca") e dieci
-- minuti prima ("Tutti in lobby", con il codice del party). Il Direttivo può anche chiamare
-- la squadra in lobby quando vuole, dal Match Day (al massimo una volta ogni 3 minuti).
-- Chi spegne "Promemoria partita" in Impostazioni non riceve i due automatici; la chiamata
-- del Direttivo arriva sempre.

create table if not exists public.event_reminders (
  id bigint generated always as identity primary key,
  event_id uuid not null references public.events on delete cascade,
  -- ora = un'ora prima, lobby = dieci minuti prima, chiamata = dal Direttivo
  kind text not null check (kind in ('ora', 'lobby', 'chiamata')),
  sent_at timestamptz not null default now(),
  sent_by uuid references public.profiles on delete set null
);
-- I due automatici partono una volta sola per partita.
create unique index if not exists event_reminders_auto_idx
  on public.event_reminders (event_id, kind) where kind <> 'chiamata';
create index if not exists event_reminders_event_idx
  on public.event_reminders (event_id, sent_at desc);
alter table public.event_reminders enable row level security;  -- nessuna policy: solo il server

-- Ogni minuto (pg_cron): gli avvisi delle partite che iniziano entro un'ora.
create or replace function public.match_reminders_tick() returns void
language plpgsql security definer set search_path = public as $$
declare
  now_ timestamptz := app_now();
  e record;
begin
  for e in
    select id, starts_at, created_at from events
    where type in ('torneo', 'amichevole')
      and starts_at > now_ and starts_at <= now_ + interval '60 minutes'
  loop
    -- Un'ora prima: solo se la partita era già in calendario (appena creata ha già avuto
    -- la sua notifica) e se manca ancora abbastanza al richiamo in lobby.
    if e.starts_at - interval '60 minutes' <= now_
       and e.starts_at > now_ + interval '15 minutes'
       and e.created_at < e.starts_at - interval '60 minutes' then
      insert into event_reminders (event_id, kind) values (e.id, 'ora')
      on conflict do nothing;
      if found then
        perform notify_push(jsonb_build_object('kind', 'match_reminder', 'id', e.id, 'when', 'ora'));
      end if;
    end if;
    -- Dieci minuti prima: tutti in lobby.
    if e.starts_at - interval '10 minutes' <= now_ then
      insert into event_reminders (event_id, kind) values (e.id, 'lobby')
      on conflict do nothing;
      if found then
        perform notify_push(jsonb_build_object('kind', 'match_reminder', 'id', e.id, 'when', 'lobby'));
      end if;
    end if;
  end loop;
end $$;
revoke all on function public.match_reminders_tick() from public, anon, authenticated;

do $$ begin
  perform cron.schedule('promemoria-partite', '* * * * *', 'select public.match_reminders_tick()');
end $$;

-- Il Direttivo chiama la squadra in lobby: da due ore prima a due ore dopo l'inizio di una
-- partita, al massimo una volta ogni 3 minuti. Restituisce l'ora della chiamata.
create or replace function public.call_to_lobby(p_event uuid) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare
  now_ timestamptz := app_now();
  e record;
  sent timestamptz;
begin
  if not is_direttivo() then
    raise exception 'Solo il Direttivo chiama la squadra in lobby';
  end if;
  select id, type, starts_at into e from events where id = p_event for update;
  if not found or e.type not in ('torneo', 'amichevole') then
    raise exception 'Partita non trovata';
  end if;
  if now_ < e.starts_at - interval '2 hours' or now_ > e.starts_at + interval '2 hours' then
    raise exception 'Si chiama la squadra solo nelle ore della partita';
  end if;
  if exists (select 1 from event_reminders
             where event_id = p_event and kind = 'chiamata'
               and sent_at > now_ - interval '3 minutes') then
    raise exception 'La squadra è stata chiamata da poco: riprova tra qualche minuto';
  end if;
  insert into event_reminders (event_id, kind, sent_at, sent_by)
  values (p_event, 'chiamata', now_, auth.uid())
  returning sent_at into sent;
  perform notify_push(jsonb_build_object('kind', 'match_reminder', 'id', p_event, 'when', 'chiamata'));
  return sent;
end $$;
revoke all on function public.call_to_lobby(uuid) from public, anon;
grant execute on function public.call_to_lobby(uuid) to authenticated;
