-- Impostazioni del profilo: foto caricata dal membro e dati anagrafici.
-- Ognuno modifica i propri (policy "modifica proprio profilo"); sono visibili ai membri del club.
alter table public.profiles
  add column if not exists avatar_path text,          -- foto nel bucket "avatars" (cartella = id utente)
  add column if not exists birth_date date,
  add column if not exists city text,
  add column if not exists nationality text,          -- codice ISO a 2 lettere (IT, ES...)
  add column if not exists preferred_foot text;

alter table public.profiles drop constraint if exists profiles_avatar_path_check;
alter table public.profiles add constraint profiles_avatar_path_check
  check (avatar_path is null or avatar_path like id::text || '/%');
alter table public.profiles drop constraint if exists profiles_birth_date_check;
alter table public.profiles add constraint profiles_birth_date_check
  check (birth_date is null or birth_date between date '1940-01-01' and current_date);
alter table public.profiles drop constraint if exists profiles_city_check;
alter table public.profiles add constraint profiles_city_check
  check (city is null or char_length(city) <= 60);
alter table public.profiles drop constraint if exists profiles_nationality_check;
alter table public.profiles add constraint profiles_nationality_check
  check (nationality is null or nationality ~ '^[A-Z]{2}$');
alter table public.profiles drop constraint if exists profiles_preferred_foot_check;
alter table public.profiles add constraint profiles_preferred_foot_check
  check (preferred_foot is null or preferred_foot in ('destro', 'sinistro', 'ambidestro'));
