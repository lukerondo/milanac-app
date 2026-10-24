-- Carte FUT (ottobre 2026): le sei statistiche della carta, decise dal Direttivo come
-- l'overall. In ordine: VEL TIR PAS DRI DIF FIS (per i portieri TUF PRE RIN RIF VEL PIA,
-- come le carte di FC). La foto della carta resta in avatar_path (bucket avatars, PNG
-- scontornato o JPEG): sulle carte va la foto, nel resto dell'app il volto disegnato.

alter table public.profiles add column if not exists card_stats smallint[];
alter table public.profiles drop constraint if exists profiles_card_stats_check;
alter table public.profiles add constraint profiles_card_stats_check check (
  card_stats is null or (
    cardinality(card_stats) = 6
    and array_position(card_stats, null) is null
    and 1 <= all (card_stats)
    and 99 >= all (card_stats)
  )
);

-- Le statistiche le cambia solo il Direttivo (come ruolo, squadre, stato e overall).
create or replace function public.prevent_self_role_change() returns trigger
language plpgsql as $$
begin
  if current_setting('milanac.registration', true) = '1' then
    perform set_config('milanac.registration', '', true);
    return new;
  end if;
  -- auth.uid() è null dall'editor SQL / service role.
  if auth.uid() is not null and not is_direttivo() and (
       new.club_role is distinct from old.club_role
    or new.requested_role is distinct from old.requested_role
    or new.teams is distinct from old.teams
    or new.active is distinct from old.active
    or new.joined_at is distinct from old.joined_at
    or new.overall is distinct from old.overall
    or new.card_stats is distinct from old.card_stats
    or new.direttivo_roles is distinct from old.direttivo_roles
    or new.registration_completed_at is distinct from old.registration_completed_at
    or new.rules_accepted_version is distinct from old.rules_accepted_version
    or new.rules_accepted_at is distinct from old.rules_accepted_at) then
    raise exception 'Solo il Direttivo può cambiare ruolo, squadra, stato, overall, statistiche della carta o data d''ingresso';
  end if;
  return new;
end $$;
