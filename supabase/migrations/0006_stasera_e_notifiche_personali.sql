-- Blocco A: formazione "pubblicata" e notifiche push personali.

-- Formazione: bozza finché il Direttivo non la pubblica.
alter table public.formations
  add column if not exists published_at timestamptz,
  add column if not exists published_by uuid references public.profiles on delete set null;

-- Token FCM dei dispositivi (uno per telefono). Ognuno gestisce solo i propri.
create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles on delete cascade,
  platform text,
  updated_at timestamptz not null default now()
);
alter table public.device_tokens enable row level security;
drop policy if exists "propri token" on public.device_tokens;
create policy "propri token" on public.device_tokens for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Configurazione interna (URL e segreto della funzione notify): nessun accesso dalle app.
create table if not exists public.app_config (
  key text primary key,
  value text not null
);
alter table public.app_config enable row level security;

-- Chiamate HTTP dal database verso la funzione "notify".
create extension if not exists pg_net with schema extensions;

create or replace function public.notify_push(payload jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  fn_url text := (select value from app_config where key = 'notify_url');
  fn_secret text := (select value from app_config where key = 'notify_secret');
begin
  if fn_url is null or fn_secret is null then
    return; -- funzione non ancora pubblicata: nessuna notifica, nessun errore
  end if;
  perform net.http_post(
    url := fn_url,
    body := payload,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-milanac-secret', fn_secret)
  );
end $$;
revoke all on function public.notify_push(jsonb) from public, anon, authenticated;

-- Quando una formazione viene pubblicata (o ripubblicata) parte la notifica a ogni membro.
create or replace function public.on_formation_published() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.published_at is not null
     and new.published_at is distinct from old.published_at then
    perform notify_push(jsonb_build_object('kind', 'formation', 'id', new.id));
  end if;
  return new;
end $$;

drop trigger if exists formation_published on public.formations;
create trigger formation_published after update of published_at on public.formations
  for each row execute function public.on_formation_published();
