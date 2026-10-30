-- Poteri del Direttivo (ottobre 2026). Tutti i membri del Direttivo hanno gli stessi poteri.
--  1) Promuovere un giocatore nel Direttivo (con le sue etichette) o retrocederlo: se ne
--     tiene traccia nella Sala Direttivo e il club non resta mai senza un Direttivo attivo.
--  2) Eliminare definitivamente l'account di un altro membro (anche di chi si è registrato
--     ma non è mai entrato); l'ultimo del Direttivo non può eliminare il proprio.
--  3) Togliere la foto del profilo di un membro (moderazione).
--  4) Chiudere una stanza vocale per tutti.

-- ---------------------------------------------------------------- 1) promozioni
-- Retrocedendo, le etichette del Direttivo (Capitano, Reclutatore...) si azzerano; il
-- Direttivo non resta mai vuoto (retrocessione o rimozione dell'ultimo membro attivo).
-- Chi si registra come Direttivo ha le etichette già da "in attesa": quelle restano.
create or replace function public.direttivo_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.club_role = 'direttivo' and new.club_role <> 'direttivo' then
    new.direttivo_roles := '{}';
  end if;
  if old.club_role = 'direttivo' and old.active
     and (new.club_role <> 'direttivo' or not new.active)
     and not exists (select 1 from profiles p
                     where p.id <> old.id and p.club_role = 'direttivo' and p.active) then
    raise exception 'Il club deve avere almeno un membro del Direttivo: nominane prima un altro';
  end if;
  return new;
end $$;
drop trigger if exists direttivo_guard on public.profiles;
create trigger direttivo_guard before update of club_role, active, direttivo_roles
  on public.profiles for each row execute function public.direttivo_guard();

-- Chi entra o esce dal Direttivo: messaggio nella Sala Direttivo (che manda anche la notifica:
-- così il nuovo membro lo sa subito) con chi l'ha deciso. L'ingresso nel club ha il suo avviso.
create or replace function public.on_direttivo_changed() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  ch uuid := (select id from channels where slug = 'direttivo');
  chi text := (select display_name from profiles where id = auth.uid());
  etichette text;
begin
  if ch is null or old.club_role = 'pending' or new.club_role = 'pending' then
    return new;
  end if;
  if new.club_role = 'direttivo' then
    select string_agg(initcap(r), ', ' order by r) into etichette from unnest(new.direttivo_roles) r;
    insert into messages (channel_id, author_id, kind, body, meta)
    values (ch, auth.uid(), 'system',
            left(new.display_name || ' è entrato nel Direttivo'
                 || coalesce(' (' || etichette || ')', '')
                 || coalesce(' · nominato da ' || chi, '') || '.', 2000),
            jsonb_build_object('type', 'direttivo', 'member', new.id, 'role', 'direttivo'));
  elsif old.club_role = 'direttivo' then
    insert into messages (channel_id, author_id, kind, body, meta)
    values (ch, auth.uid(), 'system',
            left(new.display_name || ' non fa più parte del Direttivo'
                 || coalesce(' · deciso da ' || chi, '') || '.', 2000),
            jsonb_build_object('type', 'direttivo', 'member', new.id, 'role', new.club_role));
  end if;
  return new;
end $$;
drop trigger if exists direttivo_changed on public.profiles;
create trigger direttivo_changed after update of club_role on public.profiles
  for each row when (old.club_role is distinct from new.club_role)
  execute function public.on_direttivo_changed();

-- ---------------------------------------------------------------- 2) eliminazione degli account
-- Il proprio: come prima, ma l'ultimo del Direttivo deve prima nominarne un altro.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Non autenticato';
  end if;
  if exists (select 1 from profiles where id = uid and club_role = 'direttivo' and active)
     and not exists (select 1 from profiles
                     where id <> uid and club_role = 'direttivo' and active) then
    raise exception 'Sei l''ultimo membro del Direttivo: prima nomina un altro Direttivo dalla Rosa';
  end if;
  insert into storage_cleanup (bucket, path)
  select 'avatars', o.name from storage.objects o
  where o.bucket_id = 'avatars' and (storage.foldername(o.name))[1] = uid::text
  on conflict do nothing;
  delete from auth.users where id = uid;
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Quello di un altro membro (solo Direttivo): definitivo, con traccia nella Sala Direttivo.
-- Il proprio si elimina da Impostazioni → Account (con il controllo dell'ultimo Direttivo).
create or replace function public.delete_member_account(p_member uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  uid uuid := auth.uid();
  ch uuid := (select id from public.channels where slug = 'direttivo');
  nome text;
  chi text;
begin
  if not is_direttivo() then
    raise exception 'Solo il Direttivo può eliminare l''account di un membro';
  end if;
  if p_member is null or p_member = uid then
    raise exception 'Il tuo account si elimina da Impostazioni → Account';
  end if;
  select display_name into nome from public.profiles where id = p_member;
  if nome is null then
    raise exception 'Membro non trovato';
  end if;
  select display_name into chi from public.profiles where id = uid;
  insert into storage_cleanup (bucket, path)
  select 'avatars', o.name from storage.objects o
  where o.bucket_id = 'avatars' and (storage.foldername(o.name))[1] = p_member::text
  on conflict do nothing;
  if ch is not null then
    insert into public.messages (channel_id, author_id, kind, body, meta)
    values (ch, uid, 'system',
            left('Account di ' || nome || ' eliminato da ' || coalesce(chi, 'il Direttivo') || '.', 2000),
            jsonb_build_object('type', 'account_deleted'));
  end if;
  delete from auth.users where id = p_member;
end $$;
revoke all on function public.delete_member_account(uuid) from public, anon;
grant execute on function public.delete_member_account(uuid) to authenticated;

-- ---------------------------------------------------------------- 3) foto del profilo
-- Il Direttivo può togliere la foto di un membro (il riferimento in profiles lo cambia già).
drop policy if exists "direttivo toglie foto profilo" on storage.objects;
create policy "direttivo toglie foto profilo" on storage.objects for delete
  using (bucket_id = 'avatars' and is_direttivo());

-- ---------------------------------------------------------------- 4) stanza vocale
-- Il Direttivo chiude la stanza per tutti: le sessioni aperte finiscono (il segno di vita
-- di ogni telefono risponde "non sei più dentro") e la stanza si chiude.
create or replace function public.close_voice_room(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_direttivo() then
    raise exception 'Solo il Direttivo può chiudere la stanza per tutti';
  end if;
  if not exists (select 1 from voice_rooms where id = p_room) then
    raise exception 'Stanza non trovata';
  end if;
  update voice_sessions set left_at = app_now() where room_id = p_room and left_at is null;
  update voice_rooms set closed_at = app_now() where id = p_room and closed_at is null;
end $$;
revoke all on function public.close_voice_room(uuid) from public, anon;
grant execute on function public.close_voice_room(uuid) to authenticated;
