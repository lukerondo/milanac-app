-- Due squadre: MILANAC (prima squadra) e MILANAC FUTURO (riserve).
-- Un giocatore può stare in una o in entrambe; lo decide solo il Direttivo.

alter table public.profiles
  add column if not exists teams text[] not null default array['milanac'];
alter table public.profiles drop constraint if exists profiles_teams_check;
alter table public.profiles add constraint profiles_teams_check
  check (cardinality(teams) between 1 and 2 and teams <@ array['milanac', 'futuro']);

-- Il membro può modificare il proprio profilo (nome, gamertag...), ma non ruolo, squadre,
-- stato (attivo/rimosso) e data d'ingresso: quelli li decide il Direttivo.
create or replace function public.prevent_self_role_change() returns trigger
language plpgsql as $$
begin
  -- auth.uid() è null dall'editor SQL / service role: serve per nominare il primo Direttivo.
  if auth.uid() is not null and not is_direttivo() and (
       new.club_role is distinct from old.club_role
    or new.teams is distinct from old.teams
    or new.active is distinct from old.active
    or new.joined_at is distinct from old.joined_at) then
    raise exception 'Solo il Direttivo può cambiare ruolo, squadra, stato o data d''ingresso';
  end if;
  return new;
end $$;

-- Una formazione per squadra.
alter table public.formations
  add column if not exists team text not null default 'milanac';
alter table public.formations drop constraint if exists formations_team_check;
alter table public.formations add constraint formations_team_check check (team in ('milanac', 'futuro'));

-- Eventi: di una squadra o di tutto il club (team nullo).
alter table public.events add column if not exists team text;
alter table public.events drop constraint if exists events_team_check;
alter table public.events add constraint events_team_check check (team is null or team in ('milanac', 'futuro'));

-- Partite: sempre di una squadra.
alter table public.matches
  add column if not exists team text not null default 'milanac';
alter table public.matches drop constraint if exists matches_team_check;
alter table public.matches add constraint matches_team_check check (team in ('milanac', 'futuro'));
