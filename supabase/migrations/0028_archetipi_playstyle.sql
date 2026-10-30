-- Archetipi e PlayStyle (ottobre 2026). L'archetipo resta lo stile di gioco della carta
-- (play_style, testo libero con l'elenco proposto nell'app). I PlayStyle sono codici
-- ("tiro_potente", "scatto"...) e i PlayStyle+ hanno il "+" in fondo: al massimo 6, di
-- cui 2 "+", senza doppioni. Li sceglie il giocatore sulla propria carta (o il Direttivo).

create or replace function public.valid_play_styles(s text[])
returns boolean language sql immutable set search_path = public as $$
  select cardinality(s) <= 6
     and not exists (select 1 from unnest(s) x where x is null or x !~ '^[a-z_]{2,24}\+?$')
     and (select count(*) from unnest(s) x where x like '%+') <= 2
     and (select count(distinct rtrim(x, '+')) from unnest(s) x) = cardinality(s)
$$;

alter table public.profiles add column if not exists play_styles text[] not null default '{}';
alter table public.profiles drop constraint if exists profiles_play_styles_valid;
alter table public.profiles add constraint profiles_play_styles_valid
  check (public.valid_play_styles(play_styles));
