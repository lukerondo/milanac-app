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

-- Squadre: le decide il Direttivo; il giocatore non può cambiarle né riattivarsi.
select pg_temp.as_user(null);
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000c', 'c@example.com');
update profiles set club_role = 'giocatore' where id = '00000000-0000-0000-0000-00000000000c';
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
do $$ begin
  assert (select teams from profiles where id = '00000000-0000-0000-0000-00000000000c') = array['milanac'],
    'squadra predefinita MILANAC';
end $$;
select pg_temp.expect_error(
  $q$update profiles set teams = array['milanac', 'futuro'] where id = '00000000-0000-0000-0000-00000000000c'$q$,
  'Solo il Direttivo');
update profiles set gamertag = 'Nuovo_Tag' where id = '00000000-0000-0000-0000-00000000000c';

select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
update profiles set teams = array['futuro'], active = false where id = '00000000-0000-0000-0000-00000000000c';
select pg_temp.expect_error(
  $q$update profiles set teams = array['primavera'] where id = '00000000-0000-0000-0000-00000000000c'$q$,
  'profiles_teams_check');
select pg_temp.expect_error(
  $q$update profiles set teams = '{}' where id = '00000000-0000-0000-0000-00000000000c'$q$,
  'profiles_teams_check');

select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select pg_temp.expect_error(
  $q$update profiles set active = true where id = '00000000-0000-0000-0000-00000000000c'$q$,
  'Solo il Direttivo');

select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into formations (module, is_current, team) values ('4-4-2', true, 'futuro');
insert into events (type, title, starts_at, team) values ('torneo', 'Coppa', now(), 'futuro');
insert into events (type, title, starts_at) values ('allenamento', 'Allenamento', now());
insert into matches (kind, opponent, played_at, team) values ('amichevole', 'Rivali', now(), 'futuro');
select pg_temp.expect_error(
  $q$insert into matches (kind, opponent, played_at, team) values ('amichevole', 'X', now(), 'altro')$q$,
  'matches_team_check');
reset role;
do $$ begin
  assert (select gamertag from profiles where id = '00000000-0000-0000-0000-00000000000c') = 'Nuovo_Tag',
    'il giocatore modifica i propri dati personali';
  assert (select count(*) from formations where team = 'milanac') = 1, 'formazione esistente in MILANAC';
end $$;

-- Link condivisi: lettura membri, ognuno modifica i propri, il Direttivo tutti.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select count(*) from shared_links where category = 'musica') = 5, 'link musica iniziali';
end $$;
reset role;
select pg_temp.as_user(null);
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'e1@example.com'),
  ('00000000-0000-0000-0000-0000000000e2', 'e2@example.com');
update profiles set club_role = 'giocatore' where id in ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e2');
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
insert into shared_links (category, title, url, tag) values ('build', 'Build ATT', 'https://youtu.be/abc', 'ATT');
select pg_temp.expect_error(
  $q$insert into shared_links (category, title, url, created_by) values ('build', 'X', 'https://x.it', '00000000-0000-0000-0000-00000000000d')$q$,
  'row-level security');
select pg_temp.expect_error(
  $q$insert into shared_links (category, title, url) values ('build', 'X', 'javascript:alert(1)')$q$,
  'shared_links_url_check');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
update shared_links set title = 'Rubato' where tag = 'ATT';
delete from shared_links where category = 'musica';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select title from shared_links where tag = 'ATT') = 'Build ATT', 'un altro membro non modifica';
  assert (select count(*) from shared_links where category = 'musica') = 5, 'un membro non cancella i link altrui';
end $$;
delete from shared_links where tag = 'ATT';
do $$ begin
  assert (select count(*) from shared_links where category = 'build') = 0, 'il Direttivo cancella';
end $$;
reset role;

-- Carta FUT: il giocatore imposta overall/stile/piattaforma sul proprio profilo, con limiti.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
update profiles set overall = 84, play_style = 'Finalizzatore', platform = 'ps5'
  where id = '00000000-0000-0000-0000-0000000000e1';
select pg_temp.expect_error(
  $q$update profiles set overall = 120 where id = '00000000-0000-0000-0000-0000000000e1'$q$,
  'profiles_overall_check');
select pg_temp.expect_error(
  $q$update profiles set platform = 'switch' where id = '00000000-0000-0000-0000-0000000000e1'$q$,
  'profiles_platform_check');
-- Non può cambiare la carta di un altro.
update profiles set overall = 40 where id = '00000000-0000-0000-0000-0000000000e2';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
update profiles set overall = 86 where id = '00000000-0000-0000-0000-0000000000e1';
reset role;
do $$ begin
  assert (select overall from profiles where id = '00000000-0000-0000-0000-0000000000e1') = 86,
    'il Direttivo corregge l''overall';
  assert (select overall from profiles where id = '00000000-0000-0000-0000-0000000000e2') is null,
    'nessuno modifica la carta altrui';
end $$;

-- Tattiche: le pubblica solo il Direttivo, le leggono i membri.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error(
  $q$insert into tactics (title) values ('Pressing alto')$q$, 'row-level security');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into tactics (title, module, description, image_path) values ('Pressing alto', '4-3-3', 'Linea alta', 'x.jpg');
insert into storage.objects (bucket_id, name) values ('tactics', 'x.jpg');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error(
  $q$insert into storage.objects (bucket_id, name) values ('tactics', 'y.jpg')$q$, 'row-level security');
do $$ begin
  assert (select count(*) from tactics) = 1, 'il membro legge le tattiche';
  assert (select count(*) from storage.objects where bucket_id = 'tactics') = 1, 'il membro vede le immagini';
end $$;
reset role;
