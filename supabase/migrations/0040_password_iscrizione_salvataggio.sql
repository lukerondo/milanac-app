-- Password di iscrizione: il salvataggio dall'app non riusciva ("DELETE requires a WHERE
-- clause"). Su Supabase le chiamate dall'app passano dall'estensione safeupdate, che rifiuta
-- DELETE e UPDATE senza WHERE; set_signup_password (0037) azzerava i tentativi sbagliati con
-- "delete from signup_password_attempts;". Stessa funzione, con la condizione esplicita.
create or replace function public.set_signup_password(p_new text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_direttivo() then
    raise exception 'Solo il Direttivo può cambiare la password di iscrizione';
  end if;
  if coalesce(p_new, '') = '' then
    delete from app_config where key = 'signup_password_hash';
    return;
  end if;
  if char_length(p_new) < 8 or char_length(p_new) > 72 then
    raise exception 'La password di iscrizione deve avere da 8 a 72 caratteri';
  end if;
  insert into app_config (key, value) values ('signup_password_hash', crypt(p_new, gen_salt('bf', 12)))
  on conflict (key) do update set value = excluded.value;
  -- Password nuova: i tentativi sbagliati di prima non contano più.
  delete from signup_password_attempts where true;
end $$;
revoke all on function public.set_signup_password(text) from public, anon;
grant execute on function public.set_signup_password(text) to authenticated;
