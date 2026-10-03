-- Controlli sulle regole del database (RLS, trigger, notifiche), eseguiti dopo tutte le migrazioni.
-- Utenti finti: D = Direttivo, G = Giocatore, P = in attesa.
\set ON_ERROR_STOP 1

create function pg_temp.expect_error(stmt text, expected text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlerrm ilike '%' || expected || '%' then return; end if;
    raise exception 'Errore diverso da quello atteso per [%]: %', stmt, sqlerrm;
  end;
  raise exception 'Doveva fallire ma è riuscito: %', stmt;
end $$;

create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(uid::text, ''), false);
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000d', 'd@example.com', '{"full_name": "Direttore"}'),
  ('00000000-0000-0000-0000-00000000000a', 'g@example.com', '{"name": "Giocatore"}'),
  ('00000000-0000-0000-0000-00000000000b', 'p@example.com', '{}');

do $$ begin
  assert (select count(*) from profiles where club_role = 'pending') = 3, 'profili creati in attesa';
  assert (select display_name from profiles where id = '00000000-0000-0000-0000-00000000000b') = 'p',
    'nome dalla mail';
end $$;

-- Il primo Direttivo si nomina dall'editor SQL (auth.uid() nullo).
update profiles set club_role = 'direttivo' where id = '00000000-0000-0000-0000-00000000000d';

set role authenticated;

-- In attesa: vede solo se stesso, non può promuoversi.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  assert (select count(*) from profiles) = 1, 'chi è in attesa vede solo il proprio profilo';
end $$;
select pg_temp.expect_error(
  $q$update profiles set club_role = 'direttivo' where id = '00000000-0000-0000-0000-00000000000a'$q$,
  'Solo il Direttivo');

-- Il Direttivo approva.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
update profiles set club_role = 'giocatore' where id = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  assert (select club_role from profiles where id = '00000000-0000-0000-0000-00000000000a') = 'giocatore',
    'approvazione del Direttivo';
end $$;

-- Token dei dispositivi: ognuno solo i propri.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
insert into device_tokens (token, user_id, platform) values ('tok-g', '00000000-0000-0000-0000-00000000000a', 'android');
select pg_temp.expect_error(
  $q$insert into device_tokens (token, user_id) values ('tok-x', '00000000-0000-0000-0000-00000000000d')$q$,
  'row-level security');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select count(*) from device_tokens) = 0, 'i token altrui non sono visibili';
  assert (select count(*) from app_config) = 0, 'app_config non leggibile dalle app';
end $$;
select pg_temp.expect_error($q$select public.notify_push('{}')$q$, 'permission denied');

-- Formazione: il giocatore non può pubblicare, il Direttivo sì; la pubblicazione chiama "notify".
reset role;
insert into app_config (key, value) values
  ('notify_url', 'https://example.invalid/functions/v1/notify'), ('notify_secret', 's3greto');
set role authenticated;

select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into formations (id, module, is_current) values ('00000000-0000-0000-0000-0000000000f1', '4-3-3', true);
insert into formation_slots (formation_id, slot_index, x, y, label, player_id)
  values ('00000000-0000-0000-0000-0000000000f1', 0, .5, .9, 'POR', '00000000-0000-0000-0000-00000000000a');

select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
update formations set published_at = now() where id = '00000000-0000-0000-0000-0000000000f1';
do $$ begin
  assert (select published_at from formations) is null, 'il giocatore non pubblica (RLS)';
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
update formations set published_at = now(), published_by = '00000000-0000-0000-0000-00000000000d'
  where id = '00000000-0000-0000-0000-0000000000f1';
update formations set module = '4-4-2' where id = '00000000-0000-0000-0000-0000000000f1';

reset role;
do $$ begin
  assert (select count(*) from net.calls) = 1, 'una sola notifica: solo alla pubblicazione';
  assert (select body->>'kind' from net.calls) = 'formation', 'notifica di tipo formazione';
  assert (select headers->>'x-milanac-secret' from net.calls) = 's3greto', 'segreto nell''header';
end $$;

-- Eliminazione account: profilo e token spariscono, la formazione resta.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  assert (select count(*) from device_tokens) = 0, 'token rimossi con l''account';
  assert (select player_id from formation_slots) is null, 'posto in formazione liberato';
end $$;
