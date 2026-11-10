-- Foto ritagliate dallo sfondo (novembre 2026). Sulle carte il giocatore compare senza lo
-- sfondo della foto, come nelle carte da collezione. Il ritaglio lo prepara il server
-- (tools/ritaglio_foto, lanciato dal workflow "Ritagli" di GitHub) qualche minuto dopo il
-- caricamento: finché non c'è, la carta mostra la foto intera.
--
-- Il file sta accanto alla foto, nel bucket privato "avatars": `<id>/ritaglio_<ms>.webp`
-- (il bucket accetta già image/webp e i membri lo leggono come le foto).

alter table public.profiles add column if not exists avatar_cutout_path text;
alter table public.profiles drop constraint if exists profiles_avatar_cutout_path_check;
alter table public.profiles add constraint profiles_avatar_cutout_path_check
  check (avatar_cutout_path is null or avatar_cutout_path like id::text || '/%');

-- Foto che il server non è riuscito a ritagliare (file illeggibile, nessuna persona
-- riconosciuta): non le riprova a ogni giro. Solo il server la legge e la scrive.
create table if not exists public.cutout_failures (
  avatar_path text primary key,
  reason text,
  failed_at timestamptz not null default now()
);
alter table public.cutout_failures enable row level security;

-- Il ritaglio vale per una foto sola: cambiandola o togliendola si azzera (e si dimentica
-- l'eventuale errore di quella vecchia). Lo scrive soltanto il server, che non ha un
-- utente collegato: un membro non può puntarlo altrove, può solo perderlo cambiando foto.
create or replace function public.avatar_cutout_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.avatar_path is distinct from old.avatar_path then
    new.avatar_cutout_path := null;
    if old.avatar_path is not null then
      delete from cutout_failures where avatar_path = old.avatar_path;
    end if;
  elsif new.avatar_cutout_path is distinct from old.avatar_cutout_path
        and auth.uid() is not null then
    new.avatar_cutout_path := old.avatar_cutout_path;
  end if;
  return new;
end $$;
revoke all on function public.avatar_cutout_guard() from public, anon, authenticated;

drop trigger if exists avatar_cutout_guard on public.profiles;
create trigger avatar_cutout_guard
  before update of avatar_path, avatar_cutout_path on public.profiles
  for each row execute function public.avatar_cutout_guard();
