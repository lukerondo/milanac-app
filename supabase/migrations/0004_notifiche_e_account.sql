-- Notifiche push: segna cosa è già stato notificato (evita doppioni tra un'esecuzione e l'altra).
alter table news add column if not exists notified_at timestamptz;
alter table events add column if not exists notified_at timestamptz;

-- I contenuti creati da un membro restano anche se il suo account viene eliminato.
alter table formations drop constraint if exists formations_updated_by_fkey,
  add constraint formations_updated_by_fkey foreign key (updated_by) references profiles on delete set null;
alter table events drop constraint if exists events_created_by_fkey,
  add constraint events_created_by_fkey foreign key (created_by) references profiles on delete set null;
alter table match_media drop constraint if exists match_media_uploaded_by_fkey,
  add constraint match_media_uploaded_by_fkey foreign key (uploaded_by) references profiles on delete set null;
alter table pages drop constraint if exists pages_updated_by_fkey,
  add constraint pages_updated_by_fkey foreign key (updated_by) references profiles on delete set null;

-- Eliminazione dell'account dall'app (obbligatoria per l'App Store).
-- Cancella l'utente di autenticazione: profilo e presenze vengono rimossi a cascata.
create or replace function delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then
    raise exception 'Non autenticato';
  end if;
  delete from storage.objects where bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text;
  delete from auth.users where id = auth.uid();
end $$;

revoke all on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;
