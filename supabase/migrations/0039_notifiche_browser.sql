-- Notifiche nel browser (novembre 2026). La web app riceve le stesse notifiche dei telefoni
-- con Web Push: il browser si iscrive con la chiave pubblica del club (VAPID), l'iscrizione
-- resta qui e la funzione notify le spedisce i messaggi cifrati. Niente Firebase.
--
-- La chiave pubblica sta in app_config (vapid_public_key): la scrive il workflow "Funzioni"
-- quando genera la coppia; la privata resta tra i segreti della funzione.

-- Un browser iscritto (uno per riga): l'indirizzo del servizio push e le due chiavi con cui
-- solo quel browser decifra. Ognuno vede e toglie le proprie; si scrive con la funzione qui
-- sotto.
create table if not exists public.web_push_subscriptions (
  endpoint text primary key,
  user_id uuid not null references public.profiles on delete cascade,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint web_push_endpoint_check check (
    char_length(endpoint) <= 2000
    -- Solo i servizi push dei browser (Chrome e derivati, Firefox, Edge, Safari): è la
    -- funzione notify a chiamare questo indirizzo, non deve poterne chiamare altri.
    and endpoint ~ '^https://([a-z0-9-]+\.)*(googleapis\.com|push\.services\.mozilla\.com|notify\.windows\.com|push\.apple\.com)/'
  ),
  constraint web_push_keys_check check (
    p256dh ~ '^[A-Za-z0-9_-]{80,100}$' and auth ~ '^[A-Za-z0-9_-]{16,40}$'
  )
);
create index if not exists web_push_subscriptions_user_idx on public.web_push_subscriptions (user_id);
alter table public.web_push_subscriptions enable row level security;
drop policy if exists "proprie iscrizioni" on public.web_push_subscriptions;
create policy "proprie iscrizioni" on public.web_push_subscriptions for select
  using (user_id = auth.uid());
drop policy if exists "toglie le proprie iscrizioni" on public.web_push_subscriptions;
create policy "toglie le proprie iscrizioni" on public.web_push_subscriptions for delete
  using (user_id = auth.uid());

-- La chiave pubblica con cui il browser si iscrive; null finché non è stata generata.
create or replace function public.web_push_public_key() returns text
language sql stable security definer set search_path = public as $$
  select value from app_config where key = 'vapid_public_key'
$$;
revoke all on function public.web_push_public_key() from public, anon;
grant execute on function public.web_push_public_key() to authenticated;

-- Registra (o rinnova) l'iscrizione di questo browser per chi è collegato. Se lo stesso
-- browser era iscritto con un altro account, l'iscrizione passa a quello attuale: le
-- notifiche di chi è uscito non arrivano più qui. Al massimo 10 browser a testa: oltre,
-- esce il più vecchio.
create or replace function public.register_web_push(p_endpoint text, p_p256dh text, p_auth text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Non autenticato';
  end if;
  if not exists (select 1 from profiles where id = uid and active and club_role <> 'pending') then
    raise exception 'Le notifiche sono per i membri del club';
  end if;
  insert into web_push_subscriptions (endpoint, user_id, p256dh, auth)
  values (p_endpoint, uid, p_p256dh, p_auth)
  on conflict (endpoint) do update
    set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
        updated_at = now();
  delete from web_push_subscriptions
  where user_id = uid and endpoint in (
    select endpoint from web_push_subscriptions
    where user_id = uid order by updated_at desc, endpoint offset 10
  );
exception when check_violation then
  raise exception 'Iscrizione alle notifiche non valida';
end $$;
revoke all on function public.register_web_push(text, text, text) from public, anon;
grant execute on function public.register_web_push(text, text, text) to authenticated;
