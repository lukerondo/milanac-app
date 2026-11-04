-- Nomi delle squadre come nel regolamento ufficiale 2026: MILANAC e MILANAC FUTURO (prima
-- "Milan AC" e "Milan AC Futuro"). Cambiano i nomi dei canali delle squadre (se il Direttivo non
-- li aveva già rinominati), il nome usato nei risultati e nelle carte speciali (team_name) e
-- l'annuncio della formazione in Comunicazioni.

update public.channels set name = 'MILANAC' where slug = 'milanac' and name = 'Milan AC';
update public.channels set name = 'MILANAC FUTURO' where slug = 'futuro' and name = 'Milan AC Futuro';

-- Risultato "MILANAC 3–1 Rivali".
create or replace function public.team_name(p_team text) returns text
language sql immutable as $$
  select case p_team when 'futuro' then 'MILANAC FUTURO' else 'MILANAC' end
$$;

-- Come nella 0035, con il nome della squadra da team_name.
create or replace function public.on_formation_published() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  ch uuid := (select id from channels where slug = 'comunicazioni');
  squadra text := team_name(new.team);
  titolari text;
  panchina text;
begin
  if new.published_at is null or new.published_at is not distinct from old.published_at then
    return new;
  end if;
  perform notify_push(jsonb_build_object('kind', 'formation', 'id', new.id));
  if ch is null then return new; end if;
  select string_agg(s.label || ' ' || p.display_name, ', ' order by s.slot_index)
    into titolari
  from formation_slots s join profiles p on p.id = s.player_id
  where s.formation_id = new.id and p.active and p.club_role <> 'pending';
  select string_agg(p.display_name, ', ' order by p.display_name) into panchina
  from profiles p
  where p.active and p.club_role <> 'pending' and new.team = any(p.teams)
    and not exists (select 1 from formation_slots s
                    where s.formation_id = new.id and s.player_id = p.id);
  insert into messages (channel_id, author_id, kind, body, meta)
  values (ch, new.published_by, 'system',
          'Formazione ' || squadra || ' (' || coalesce(new.published_module, new.module) || '): '
          || coalesce(titolari, 'da definire')
          || case when panchina is null then '' else '. Panchina: ' || panchina end
          || coalesce(E'\n' || set_pieces_line(new.published_set_pieces), ''),
          jsonb_build_object('type', 'formation', 'team', new.team, 'id', new.id));
  return new;
end $$;
