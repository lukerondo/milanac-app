-- Palle inattive (novembre 2026). Il regolamento: "Le responsabilità sui calci d'angolo,
-- punizioni e rigori ... sono definite in anticipo dallo staff tecnico". La formazione dice
-- anche chi batte: un giocatore per ruolo (rigori, punizioni, angoli da sinistra, angoli da
-- destra), lo stesso può batterne più d'uno, ogni ruolo è facoltativo e il battitore è
-- sempre un titolare.
--  1) formations.set_pieces (bozza) e published_set_pieces ("congelati" alla
--     pubblicazione, come published_players): {"rigori": id, "punizioni": id,
--     "angoli_sx": id, "angoli_dx": id}. Permessi come il resto della formazione
--     ("lettura membri", "scrittura direttivo").
--  2) save_formation salva anche i battitori; le app che non li conoscono li lasciano
--     com'erano (tolti quelli usciti dal campo).
--  3) Alla pubblicazione restano solo i battitori tra i titolari pubblicati; l'annuncio in
--     Comunicazioni aggiunge la riga "Palle inattive: rigori Rossi · punizioni ...".

-- ---------------------------------------------------------------- 1) battitori
-- Un oggetto con i soli ruoli noti e, per valore, l'id (uuid) di un giocatore.
create or replace function public.valid_set_pieces(s jsonb) returns boolean
language sql immutable as $$
  select case
    when s is null then false
    when jsonb_typeof(s) <> 'object' then false
    else not exists (
      select 1 from jsonb_each(s) e
      where e.key not in ('rigori', 'punizioni', 'angoli_sx', 'angoli_dx')
         or jsonb_typeof(e.value) <> 'string'
         or (e.value #>> '{}') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    )
  end
$$;

alter table public.formations
  add column if not exists set_pieces jsonb not null default '{}'::jsonb,
  add column if not exists published_set_pieces jsonb;
alter table public.formations drop constraint if exists formations_set_pieces_valid;
alter table public.formations
  add constraint formations_set_pieces_valid check (public.valid_set_pieces(set_pieces));
alter table public.formations drop constraint if exists formations_published_set_pieces_valid;
alter table public.formations
  add constraint formations_published_set_pieces_valid
  check (published_set_pieces is null or public.valid_set_pieces(published_set_pieces));

-- I battitori della bozza sono titolari della bozza (anche scritti direttamente in tabella:
-- dalla policy "scrittura direttivo"). Alla pubblicazione restano solo quelli tra i
-- titolari pubblicati; un'app che non conosce i battitori non li manda, e valgono quelli
-- della bozza.
create or replace function public.formations_set_pieces() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.set_pieces is distinct from old.set_pieces then
    -- (Il trigger viene prima dei vincoli: il testo dell'errore lo dà lui.)
    if not valid_set_pieces(new.set_pieces) then
      raise exception 'Palle inattive non valide';
    end if;
    if exists (select 1 from jsonb_each_text(new.set_pieces) e
               where not exists (select 1 from formation_slots s
                                 where s.formation_id = new.id
                                   and s.player_id::text = e.value)) then
      raise exception 'Chi batte le palle inattive deve essere tra i titolari';
    end if;
  end if;
  if tg_op = 'UPDATE' and new.published_at is distinct from old.published_at
     and new.published_set_pieces is not distinct from old.published_set_pieces then
    new.published_set_pieces := new.set_pieces;
  end if;
  if new.published_set_pieces is not null and not valid_set_pieces(new.published_set_pieces) then
    raise exception 'Palle inattive non valide';
  end if;
  if new.published_set_pieces is not null then
    new.published_set_pieces := coalesce((
      select jsonb_object_agg(e.key, e.value)
      from jsonb_each_text(new.published_set_pieces) e
      where exists (select 1 from jsonb_each_text(coalesce(new.published_players, '{}'::jsonb)) p
                    where p.value = e.value)), '{}'::jsonb);
  end if;
  return new;
end $$;
drop trigger if exists formations_set_pieces on public.formations;
create trigger formations_set_pieces before insert or update on public.formations
  for each row execute function public.formations_set_pieces();

-- ---------------------------------------------------------------- 2) salvataggio
-- Come nella 0023, con i battitori ({"rigori": id, ...}; null = app che non li conosce:
-- restano quelli di prima ancora in campo). I battitori si scrivono dopo i posti, così il
-- controllo li trova già tra i titolari.
drop function if exists public.save_formation(uuid, text, text, jsonb);
create or replace function public.save_formation(p_id uuid, p_team text, p_module text, p_slots jsonb,
                                                 p_set_pieces jsonb default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare fid uuid := p_id;
begin
  if not is_direttivo() then raise exception 'Solo il Direttivo prepara la formazione'; end if;
  if p_team is null or p_team not in ('milanac', 'futuro') then raise exception 'Squadra non valida'; end if;
  if coalesce(btrim(p_module), '') = '' or char_length(p_module) > 20 then
    raise exception 'Modulo non valido';
  end if;
  if p_slots is null or jsonb_typeof(p_slots) <> 'array' or jsonb_array_length(p_slots) > 11 then
    raise exception 'Formazione non valida';
  end if;
  if p_set_pieces is not null and not valid_set_pieces(p_set_pieces) then
    raise exception 'Palle inattive non valide';
  end if;
  if fid is null then
    insert into formations (module, team, is_current, updated_by, updated_at)
    values (p_module, p_team, true, auth.uid(), now()) returning id into fid;
  else
    update formations
    set module = p_module, team = p_team, is_current = true, updated_by = auth.uid(), updated_at = now()
    where id = fid;
    if not found then raise exception 'Formazione non trovata'; end if;
  end if;
  delete from formation_slots where formation_id = fid;
  insert into formation_slots (formation_id, slot_index, x, y, label, player_id)
  select fid, (s->>'slot_index')::smallint, (s->>'x')::real, (s->>'y')::real, s->>'label',
         nullif(s->>'player_id', '')::uuid
  from jsonb_array_elements(p_slots) s;
  update formations f
  set set_pieces = coalesce(p_set_pieces, (
        select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
        from jsonb_each_text(f.set_pieces) e
        where exists (select 1 from formation_slots s
                      where s.formation_id = fid and s.player_id::text = e.value)))
  where f.id = fid;
  return fid;
end $$;
revoke all on function public.save_formation(uuid, text, text, jsonb, jsonb) from public, anon;
grant execute on function public.save_formation(uuid, text, text, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------- 3) annuncio
-- "Palle inattive: rigori Rossi · punizioni Bianchi · angoli sx Verdi, dx Neri" (null senza
-- battitori; chi è uscito dal club non si scrive). Le stesse regole di setPiecesLine
-- nell'app (lib/features/formazione/modules.dart).
create or replace function public.set_pieces_line(p_takers jsonb) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  n jsonb;
  parts text[] := '{}';
begin
  select coalesce(jsonb_object_agg(e.key, p.display_name), '{}'::jsonb) into n
  from jsonb_each_text(coalesce(p_takers, '{}'::jsonb)) e
  join profiles p on p.id::text = e.value
  where p.active and p.club_role <> 'pending';
  if n ? 'rigori' then parts := parts || ('rigori ' || (n->>'rigori')); end if;
  if n ? 'punizioni' then parts := parts || ('punizioni ' || (n->>'punizioni')); end if;
  if n ? 'angoli_sx' and n ? 'angoli_dx' then
    parts := parts || case when p_takers->>'angoli_sx' = p_takers->>'angoli_dx'
                           then 'angoli ' || (n->>'angoli_sx')
                           else 'angoli sx ' || (n->>'angoli_sx') || ', dx ' || (n->>'angoli_dx') end;
  elsif n ? 'angoli_sx' then
    parts := parts || ('angoli sx ' || (n->>'angoli_sx'));
  elsif n ? 'angoli_dx' then
    parts := parts || ('angoli dx ' || (n->>'angoli_dx'));
  end if;
  if cardinality(parts) = 0 then return null; end if;
  return 'Palle inattive: ' || array_to_string(parts, ' · ');
end $$;
revoke all on function public.set_pieces_line(jsonb) from public, anon, authenticated;

-- Annuncio della formazione: come nella 0025, con i battitori su una riga in fondo.
create or replace function public.on_formation_published() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  ch uuid := (select id from channels where slug = 'comunicazioni');
  squadra text := case new.team when 'futuro' then 'Milan AC Futuro' else 'Milan AC' end;
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
