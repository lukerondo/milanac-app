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

-- Fissa "adesso" (app_now) a un orario italiano di oggi: le presenze chiudono alle 18:30.
create function pg_temp.at_rome(t text) returns void language plpgsql as $$
begin
  perform set_config('milanac.now',
    ((((now() at time zone 'Europe/Rome')::date)::text || ' ' || t)::timestamp at time zone 'Europe/Rome')::text,
    false);
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
  assert (select count(*) from messages m join channels c on c.id = m.channel_id
          where c.slug = 'comunicazioni' and m.kind = 'system' and m.meta->>'type' = 'formation') = 1,
    'formazione annunciata in Comunicazioni';
  assert (select body from messages where meta->>'type' = 'formation')
         like 'Formazione Milan AC (4-3-3): POR Giocatore%', 'testo dell''annuncio';
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
reset role;
delete from net.calls;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
-- Un giocatore propone un video (anche se chiede "pubblicato", resta una proposta).
insert into shared_links (category, title, url, tag, status) values ('video', 'Build ATT', 'https://youtu.be/abc', 'ATT', 'pubblicato');
select pg_temp.expect_error(
  $q$insert into shared_links (category, title, url, created_by) values ('video', 'X', 'https://x.it', '00000000-0000-0000-0000-00000000000d')$q$,
  'row-level security');
select pg_temp.expect_error(
  $q$insert into shared_links (category, title, url) values ('video', 'X', 'javascript:alert(1)')$q$,
  'shared_links_url_check');
select pg_temp.expect_error(
  $q$insert into shared_links (category, title, url) values ('build', 'X', 'https://x.it')$q$,
  'shared_links_category_check');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
update shared_links set title = 'Rubato' where tag = 'ATT';
delete from shared_links where category = 'musica';
do $$ begin
  assert (select count(*) from shared_links where tag = 'ATT') = 0, 'la proposta altrui non si vede';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select title from shared_links where tag = 'ATT') = 'Build ATT', 'un altro membro non modifica';
  assert (select status from shared_links where tag = 'ATT') = 'proposto', 'il giocatore può solo proporre';
  assert (select count(*) from shared_links where category = 'musica') = 5, 'un membro non cancella i link altrui';
end $$;
-- Il Direttivo pubblica: da quel momento lo vedono tutti.
update shared_links set status = 'pubblicato' where tag = 'ATT';
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
do $$ begin
  assert (select count(*) from shared_links where tag = 'ATT') = 1, 'video pubblicato visibile a tutti';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select published_by from shared_links where tag = 'ATT') = '00000000-0000-0000-0000-00000000000d',
    'chi ha pubblicato';
end $$;
delete from shared_links where tag = 'ATT';
do $$ begin
  assert (select count(*) from shared_links where category = 'video') = 0, 'il Direttivo cancella';
end $$;
reset role;
do $$ begin
  assert (select count(*) from net.calls where body->>'kind' = 'video_proposed') = 1, 'avviso della proposta';
  assert (select count(*) from net.calls where body->>'kind' = 'video_published') = 1, 'avviso della pubblicazione';
end $$;

-- Carta FUT: il giocatore imposta stile e piattaforma; l'overall lo decide il Direttivo.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
update profiles set play_style = 'Finalizzatore', platform = 'ps5'
  where id = '00000000-0000-0000-0000-0000000000e1';
select pg_temp.expect_error(
  $q$update profiles set overall = 84 where id = '00000000-0000-0000-0000-0000000000e1'$q$,
  'Solo il Direttivo');
select pg_temp.expect_error(
  $q$update profiles set platform = 'switch' where id = '00000000-0000-0000-0000-0000000000e1'$q$,
  'profiles_platform_check');
-- Non può cambiare la carta di un altro.
update profiles set play_style = 'Rubato' where id = '00000000-0000-0000-0000-0000000000e2';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select pg_temp.expect_error(
  $q$update profiles set overall = 120 where id = '00000000-0000-0000-0000-0000000000e1'$q$,
  'profiles_overall_check');
update profiles set overall = 86 where id = '00000000-0000-0000-0000-0000000000e1';
reset role;
do $$ begin
  assert (select overall from profiles where id = '00000000-0000-0000-0000-0000000000e1') = 86,
    'il Direttivo imposta l''overall';
  assert (select play_style from profiles where id = '00000000-0000-0000-0000-0000000000e2') is null,
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

-- Chat: lettura/scrittura dei membri, messaggi di sistema dalle presenze, non letti.
reset role;
select pg_temp.as_user(null);
delete from net.calls;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
insert into messages (channel_id, body) select id, 'Ciao a tutti' from channels where slug = 'main';
select pg_temp.expect_error(
  $q$insert into messages (channel_id, body, kind) select id, 'finto', 'system' from channels where slug = 'main'$q$,
  'row-level security');
select pg_temp.expect_error(
  $q$insert into messages (channel_id, body, author_id) select id, 'a nome di altri', '00000000-0000-0000-0000-00000000000d' from channels where slug = 'main'$q$,
  'row-level security');
select pg_temp.expect_error(
  $q$insert into messages (channel_id, body) select id, '   ' from channels where slug = 'main'$q$,
  'messages_check');
-- Una presenza di stasera (le risposte sono aperte alle 17:00) non produce messaggi in chat.
select pg_temp.at_rome('17:00');
insert into attendance (player_id, date, status)
values ('00000000-0000-0000-0000-0000000000e1', (now() at time zone 'Europe/Rome')::date, 'presente');
insert into channel_mutes (channel_id) select id from channels where slug = 'tattiche';

select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$
declare o record;
begin
  assert (select count(*) from messages m join channels c on c.id = m.channel_id
          where m.meta->>'type' = 'attendance') = 0, 'niente messaggi automatici per le presenze';
  assert (select count(*) from channels where slug in ('presenze', 'fantacalcio')) = 0, 'canali Presenze e Fantacalcio spariti';
  select * into o from chat_overview() where channel_id = (select id from channels where slug = 'main');
  assert o.unread = 1 and o.last_body = 'Ciao a tutti', 'non letti e ultimo messaggio per il Direttivo';
  assert (select count(*) from channel_mutes) = 0, 'i silenziati altrui non sono visibili';
end $$;
insert into channel_reads (channel_id) select id from channels where slug = 'main';
do $$ begin
  assert (select unread from chat_overview() where channel_id = (select id from channels where slug = 'main')) = 0,
    'letto dopo channel_reads';
end $$;
-- Il Direttivo può eliminare i messaggi altrui; l'autore solo i propri.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
delete from messages where body = 'Ciao a tutti';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select count(*) from messages where body = 'Ciao a tutti') = 1, 'un altro membro non elimina';
end $$;
delete from messages where body = 'Ciao a tutti';
reset role;
do $$ begin
  assert (select count(*) from messages where body = 'Ciao a tutti') = 0, 'il Direttivo elimina';
  assert (select count(*) from net.calls where body->>'kind' = 'chat_message') = 1, 'una notifica per messaggio';
end $$;

-- Tornei: li gestisce il Direttivo; eliminando un torneo le partite restano.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error(
  $q$insert into tournaments (name) values ('Coppa finta')$q$, 'row-level security');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into tournaments (id, name, organizer, url, team)
values ('00000000-0000-0000-0000-0000000000a1', 'FVPA Serie B', 'FVPA', 'https://fvpa.it', 'milanac');
insert into tournament_standings (tournament_id, team_name, won, drawn, lost, is_us)
values ('00000000-0000-0000-0000-0000000000a1', 'MILANAC', 3, 1, 0, true);
select pg_temp.expect_error(
  $q$insert into tournaments (name, url) values ('X', 'ftp://x')$q$, 'tournaments_url_check');
insert into matches (kind, opponent, played_at, tournament_id)
values ('torneo', 'Dinamo', now(), '00000000-0000-0000-0000-0000000000a1');
delete from tournaments where id = '00000000-0000-0000-0000-0000000000a1';
reset role;
do $$ begin
  assert (select count(*) from tournament_standings) = 0, 'classifica eliminata con il torneo';
  assert (select count(*) from matches where opponent = 'Dinamo' and tournament_id is null) = 1,
    'la partita resta senza torneo';
end $$;

-- Profilo: ognuno aggiorna i propri dati e carica la foto solo nella propria cartella.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
update profiles set city = 'Milano', nationality = 'IT',
  preferred_foot = 'sinistro', avatar_path = '00000000-0000-0000-0000-0000000000e1/foto.jpg'
  where id = '00000000-0000-0000-0000-0000000000e1';
insert into storage.objects (bucket_id, name) values ('avatars', '00000000-0000-0000-0000-0000000000e1/foto.jpg');
select pg_temp.expect_error(
  $q$insert into storage.objects (bucket_id, name) values ('avatars', '00000000-0000-0000-0000-0000000000e2/foto.jpg')$q$,
  'row-level security');
select pg_temp.expect_error(
  $q$update profiles set avatar_path = '00000000-0000-0000-0000-0000000000e2/foto.jpg' where id = '00000000-0000-0000-0000-0000000000e1'$q$,
  'profiles_avatar_path_check');
select pg_temp.expect_error(
  $q$update profiles set nationality = 'Italia' where id = '00000000-0000-0000-0000-0000000000e1'$q$,
  'profiles_nationality_check');
update profiles set city = 'Roma' where id = '00000000-0000-0000-0000-0000000000e2';
reset role;
do $$ begin
  assert (select city from profiles where id = '00000000-0000-0000-0000-0000000000e1') = 'Milano', 'dati salvati';
  assert (select city from profiles where id = '00000000-0000-0000-0000-0000000000e2') is null, 'dati altrui intoccabili';
end $$;

-- Sala Direttivo: il canale riservato e i suoi messaggi sono invisibili ai giocatori.
select set_config('test.canale_direttivo', (select id::text from channels where slug = 'direttivo'), false);
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into messages (channel_id, body) select id, 'Riunione segreta' from channels where slug = 'direttivo';
insert into messages (channel_id, body, meta)
  select id, 'Stasera si gioca alle 22', '{"type": "announcement"}' from channels where slug = 'main';
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
do $$ begin
  assert (select count(*) from channels where slug = 'direttivo') = 0, 'canale riservato invisibile';
  assert (select count(*) from messages where body = 'Riunione segreta') = 0, 'messaggi riservati invisibili';
  assert (select count(*) from chat_overview() o join channels c on c.id = o.channel_id) = 4,
    'il riepilogo mostra solo i canali visibili';
  assert (select count(*) from messages where body = 'Stasera si gioca alle 22') = 1, 'avviso visibile a tutti';
end $$;
select pg_temp.expect_error(
  $q$insert into messages (channel_id, body) values (current_setting('test.canale_direttivo')::uuid, 'intruso')$q$,
  'row-level security');
select pg_temp.expect_error(
  $q$insert into messages (channel_id, body, meta) select id, 'finto avviso', '{"type": "announcement"}' from channels where slug = 'main'$q$,
  'row-level security');
reset role;
do $$ begin
  assert (select count(*) from channels where direttivo_only) = 1, 'canale Sala Direttivo creato';
end $$;

-- Statistiche di sempre per i traguardi (niente più voti).
reset role;
select pg_temp.as_user(null);
delete from net.calls;
insert into matches (id, kind, opponent, played_at, team, goals_for, goals_against)
values ('00000000-0000-0000-0000-0000000000b1', 'torneo', 'Dinamo', now(), 'milanac', 2, 1),
       ('00000000-0000-0000-0000-0000000000b2', 'torneo', 'Futura', now() + interval '1 day', 'milanac', null, null);
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
do $$ begin
  assert (player_stats('00000000-0000-0000-0000-0000000000e1')->>'presences')::int = 1, 'presenze di sempre';
  assert (player_stats('00000000-0000-0000-0000-0000000000e1')->>'late')::int = 0, 'ritardi di sempre';
end $$;
-- Risultato inserito → una notifica alla squadra.
reset role;
delete from net.calls;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
update matches set goals_for = 1, goals_against = 1 where id = '00000000-0000-0000-0000-0000000000b2';
update matches set notes = 'bella partita' where id = '00000000-0000-0000-0000-0000000000b2';
reset role;
do $$ begin
  assert (select count(*) from net.calls where body->>'kind' = 'match_result') = 1,
    'una sola notifica per risultato';
end $$;

-- Registrazione: dati completi, password del Direttivo, regolamento da accettare.
reset role;
select pg_temp.as_user(null);
delete from net.calls;
-- La password del club, solo per il test (l'hash vero sta nella migrazione).
update app_config set value = crypt('prova-test', gen_salt('bf')) where key = 'direttivo_password_hash';
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'r1@example.com'),
  ('00000000-0000-0000-0000-0000000000a2', 'r2@example.com');
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
do $$ begin
  assert (select count(*) from rules_versions) = 1, 'chi si registra legge il regolamento (versione 1)';
  assert (select count(*) from pages where slug = 'storia') = 1, 'e la storia del club';
end $$;
select pg_temp.expect_error($q$select accept_rules(1)$q$, 'Completa prima');
select pg_temp.expect_error(
  $q$select complete_registration('', 'Rossi', 1995, 'ROSSI', null, array['milanac'], false, null, null, 'ATT', 9, 'ps5', '{}')$q$,
  'Nome non valido');
select pg_temp.expect_error(
  $q$select complete_registration('Mario', 'Rossi', 1995, 'NOME TROPPO LUNGO!', null, array['milanac'], false, null, null, 'ATT', 9, 'ps5', '{}')$q$,
  'massimo 14');
select pg_temp.expect_error(
  $q$select complete_registration('Mario', 'Rossi', 1995, 'ROSSI', null, array['milanac', 'futuro'], false, null, null, 'ATT', 9, 'ps5', '{}')$q$,
  'una sola squadra');
select complete_registration('Mario', 'Rossi', 1995, ' Rossi ', 'Forza Milan', array['milanac'], false, null, null, 'ATT', 9, 'ps5', '{"skin": 2}');
do $$ begin
  assert (select club_role from profiles where id = '00000000-0000-0000-0000-0000000000a1') = 'pending',
    'ancora fuori finché non accetta il regolamento';
  assert (select display_name from profiles where id = '00000000-0000-0000-0000-0000000000a1') = 'Rossi', 'nome sulla carta';
  assert (select overall from profiles where id = '00000000-0000-0000-0000-0000000000a1') = 60, 'overall iniziale 60';
  assert (select count(*) from events) = 0, 'chi non è entrato non legge i dati del club';
end $$;
select pg_temp.expect_error($q$select accept_rules(7)$q$, 'non aggiornata');
select pg_temp.expect_error(
  $q$update profiles set requested_role = 'direttivo' where id = '00000000-0000-0000-0000-0000000000a1'$q$,
  'Solo il Direttivo');
select accept_rules(1);
do $$ begin
  assert (select club_role from profiles where id = '00000000-0000-0000-0000-0000000000a1') = 'giocatore', 'entrato come giocatore';
  assert (select rules_accepted_version from profiles where id = '00000000-0000-0000-0000-0000000000a1') = 1, 'versione accettata';
  assert (select count(*) from events) >= 1, 'da membro legge i dati del club';
end $$;
select pg_temp.expect_error($q$select publish_rules()$q$, 'Solo il Direttivo');
select pg_temp.expect_error($q$select set_direttivo_password('prova-test', 'nuova-password')$q$, 'Solo il Direttivo');

-- Direttivo: serve la password del club; può stare in entrambe le squadre.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
do $$ begin
  assert (select complete_registration('Fabio', 'Bianchi', 1990, 'BIANCHI', null, array['milanac', 'futuro'], true, 'sbagliata', array['capitano'], 'CC', 10, 'ps5', '{}'))
         = 'password_errata', 'password del Direttivo sbagliata';
  assert (select requested_role from profiles where id = '00000000-0000-0000-0000-0000000000a2') = 'giocatore',
    'con la password sbagliata non si chiede il Direttivo';
end $$;
select pg_temp.expect_error(
  $q$select complete_registration('Fabio', 'Bianchi', 1990, 'BIANCHI', null, array['milanac', 'futuro'], true, 'prova-test', '{}', 'CC', 10, 'ps5', '{}')$q$,
  'almeno un ruolo');
select complete_registration('Fabio', 'Bianchi', 1990, 'BIANCHI', null, array['futuro', 'milanac', 'milanac'], true, 'prova-test', array['capitano', 'gestore'], 'CC', 10, 'ps5', '{}');
select accept_rules(1);
do $$ begin
  assert (select club_role from profiles where id = '00000000-0000-0000-0000-0000000000a2') = 'direttivo', 'entrato nel Direttivo';
  assert (select teams from profiles where id = '00000000-0000-0000-0000-0000000000a2') = array['milanac', 'futuro'],
    'squadre in ordine, senza doppioni';
  assert (select direttivo_roles from profiles where id = '00000000-0000-0000-0000-0000000000a2') = array['capitano', 'gestore'], 'etichette';
end $$;
-- Nuova versione del regolamento: notifica a tutti e nuova accettazione.
insert into rules_articles (sort_order, title, body) values (1, 'Art. 1 – Presenze', 'Rispondi entro le 18:30.');
do $$ begin
  assert (select publish_rules()) = 2, 'versione 2';
end $$;
reset role;
do $$ begin
  assert (select count(*) from net.calls where body->>'kind' = 'rules') = 1, 'notifica del nuovo regolamento';
  assert (select jsonb_array_length(snapshot) from rules_versions where number = 2) = 2, 'due articoli nella versione 2';
end $$;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.expect_error($q$select accept_rules(1)$q$, 'non aggiornata');
select accept_rules(2);
do $$ begin
  assert (select rules_accepted_version from profiles where id = '00000000-0000-0000-0000-0000000000a1') = 2, 'riaccettata la versione 2';
  assert (select count(*) from rules_articles) = 0, 'la bozza non si legge dai giocatori';
end $$;
-- Cambio della password del club.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select pg_temp.expect_error($q$select set_direttivo_password('sbagliata', 'nuova-password')$q$, 'non corretta');
select pg_temp.expect_error($q$select set_direttivo_password('prova-test', 'corta')$q$, 'almeno 8');
select set_direttivo_password('prova-test', 'nuova-password');
reset role;
do $$ begin
  assert check_direttivo_password('nuova-password'), 'nuova password attiva';
  assert not check_direttivo_password('prova-test'), 'vecchia password disattivata';
end $$;

-- Presenze: nota obbligatoria per il ritardo, risposte chiuse alle 18:30, promemoria alle 18:00
-- e assenze automatiche alle 18:30 (anche per i giorni successivi si risponde in anticipo).
reset role;
select pg_temp.as_user(null);
delete from net.calls;
set role authenticated;
select pg_temp.at_rome('17:00');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
select pg_temp.expect_error(
  $q$insert into attendance (player_id, date, status, arrival_time) values ('00000000-0000-0000-0000-0000000000e2', (now() at time zone 'Europe/Rome')::date, 'ritardo', '21:50')$q$,
  'attendance_late_note_check');
insert into attendance (player_id, date, status, arrival_time, note)
values ('00000000-0000-0000-0000-0000000000e2', (now() at time zone 'Europe/Rome')::date, 'ritardo', '21:50', 'Traffico');
insert into attendance (player_id, date, status)
values ('00000000-0000-0000-0000-0000000000e2', (now() at time zone 'Europe/Rome')::date + 1, 'presente');
-- 18:05: il promemoria va solo a chi non ha risposto per stasera (D, a1, a2).
select pg_temp.at_rome('18:05');
reset role;
select pg_temp.as_user(null);
select attendance_tick();
select attendance_tick();
do $$ begin
  assert (select count(*) from net.calls where body->>'kind' = 'attendance_reminder') = 1, 'un solo promemoria';
  assert (select jsonb_array_length(body->'users') from net.calls where body->>'kind' = 'attendance_reminder') = 3,
    'promemoria a chi non ha risposto';
  assert (select count(*) from attendance where auto) = 0, 'prima delle 18:30 nessuna assenza automatica';
end $$;
-- 18:31: i giocatori non cambiano più nulla; il Direttivo sì (e resta registrato).
set role authenticated;
select pg_temp.at_rome('18:31');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
update attendance set status = 'presente', note = null
  where player_id = '00000000-0000-0000-0000-0000000000e2' and date = (now() at time zone 'Europe/Rome')::date;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.expect_error(
  $q$insert into attendance (player_id, date, status) values ('00000000-0000-0000-0000-0000000000a1', (now() at time zone 'Europe/Rome')::date, 'presente')$q$,
  'row-level security');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select status from attendance where player_id = '00000000-0000-0000-0000-0000000000e2'
          and date = (now() at time zone 'Europe/Rome')::date) = 'ritardo', 'dopo le 18:30 il giocatore non modifica';
end $$;
update attendance set status = 'presente', note = null
  where player_id = '00000000-0000-0000-0000-0000000000e2' and date = (now() at time zone 'Europe/Rome')::date;
reset role;
select pg_temp.as_user(null);
select attendance_tick();
select attendance_tick();
do $$ begin
  assert (select status from attendance where player_id = '00000000-0000-0000-0000-0000000000e2'
          and date = (now() at time zone 'Europe/Rome')::date) = 'presente', 'il Direttivo corregge dopo le 18:30';
  assert (select set_by from attendance where player_id = '00000000-0000-0000-0000-0000000000e2'
          and date = (now() at time zone 'Europe/Rome')::date) = '00000000-0000-0000-0000-00000000000d',
    'la correzione del Direttivo resta registrata';
  assert (select count(*) from attendance where auto) = 3, 'assenze automatiche per chi non ha risposto';
  assert (select count(*) from net.calls where body->>'kind' = 'attendance_auto_absent') = 1, 'un solo avviso di assenza';
  assert (select jsonb_array_length(body->'users') from net.calls where body->>'kind' = 'attendance_auto_absent') = 3,
    'avviso a chi è risultato assente';
  assert (select count(*) from daily_jobs) = 2, 'lavori del giorno segnati una volta sola';
  assert (select count(*) from attendance where player_id = '00000000-0000-0000-0000-0000000000e2' and auto) = 0,
    'chi ha risposto non è assente d''ufficio';
end $$;
-- L'assenza automatica la corregge solo il Direttivo.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
update attendance set status = 'presente'
  where player_id = '00000000-0000-0000-0000-0000000000a1' and date = (now() at time zone 'Europe/Rome')::date;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select auto from attendance where player_id = '00000000-0000-0000-0000-0000000000a1'
          and date = (now() at time zone 'Europe/Rome')::date), 'il giocatore non toglie l''assenza automatica';
end $$;
update attendance set status = 'presente'
  where player_id = '00000000-0000-0000-0000-0000000000a1' and date = (now() at time zone 'Europe/Rome')::date;
reset role;
do $$ begin
  assert (select not auto and set_by = '00000000-0000-0000-0000-00000000000d' from attendance
          where player_id = '00000000-0000-0000-0000-0000000000a1' and date = (now() at time zone 'Europe/Rome')::date),
    'corretta dal Direttivo';
  assert (select count(*) from cron.job where jobname = 'presenze' and schedule = '* * * * *') = 1,
    'controllo delle presenze ogni minuto';
end $$;
select set_config('milanac.now', '', false);

-- Eventi: alla creazione parte la notifica alla squadra (o a tutti).
delete from net.calls;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into events (type, title, starts_at, team) values ('amichevole', 'Amichevole vs Rivali', now() + interval '2 days', 'milanac');
reset role;
do $$ begin
  assert (select count(*) from net.calls where body->>'kind' = 'event') = 1, 'notifica del nuovo evento';
end $$;

-- Canali di squadra: chi è solo in una squadra non vede l'altra; in Comunicazioni scrive solo il Direttivo.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
do $$ begin
  assert (select count(*) from channels where slug = 'milanac') = 1, 'la propria squadra si vede';
  assert (select count(*) from channels where slug = 'futuro') = 0, 'l''altra squadra no';
  assert (select count(*) from channels where slug = 'comunicazioni') = 1, 'Comunicazioni per tutti';
  assert (select count(*) from channels where slug = 'main' and name = 'Generale') = 1, 'canale Generale';
end $$;
select pg_temp.expect_error(
  $q$insert into messages (channel_id, body) select id, 'intruso' from channels where slug = 'comunicazioni'$q$,
  'row-level security');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
do $$ begin
  assert (select count(*) from channels where slug in ('milanac', 'futuro')) = 2, 'il Direttivo vede entrambe le squadre';
end $$;
insert into messages (channel_id, body) select id, 'Domenica si gioca alle 22' from channels where slug = 'comunicazioni';
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
do $$ begin
  assert (select count(*) from messages where body = 'Domenica si gioca alle 22') = 1, 'le comunicazioni si leggono';
end $$;
reset role;

-- Notizie: un avviso per gli aggiornamenti di FC 27 (a tutti) e per le console (per piattaforma),
-- al massimo uno ogni 12 ore per tipo; le notizie vecchie non avvisano.
delete from net.calls;
insert into news (source, category, title, url, published_at) values
  ('EA', 'aggiornamenti', 'Title Update 3', 'https://ea.com/tu3', now()),
  ('GN', 'aggiornamenti', 'Title Update 3 (ripresa)', 'https://gn.it/tu3', now()),
  ('GN', 'aggiornamenti', 'Vecchia patch', 'https://gn.it/old', now() - interval '10 days');
insert into news (source, category, title, url, published_at, platform) values
  ('GN', 'console', 'PS5: aggiornamento di sistema 10.02', 'https://gn.it/ps5', now(), 'ps5'),
  ('GN', 'console', 'Console senza piattaforma', 'https://gn.it/console', now(), null);
do $$ begin
  assert (select count(*) from net.calls where body->>'kind' = 'news') = 2, 'un avviso per FC 27 e uno per PS5';
  assert (select notified_at is not null from news where url = 'https://ea.com/tu3'), 'avvisata';
  assert (select notified_at is null from news where url = 'https://gn.it/tu3'), 'ripresa non avvisata';
  assert (select notified_at is null from news where url = 'https://gn.it/old'), 'vecchia non avvisata';
end $$;
select pg_temp.expect_error(
  $q$insert into news (source, category, title, url, platform) values ('GN', 'console', 'X', 'https://gn.it/x3', 'switch')$q$,
  'news_platform_check');

-- Chat (Fase 3): si risponde solo nello stesso canale, vocali fino a 2 minuti, foto e vocali
-- scadono dopo 60 giorni e i file finiscono in coda per la pulizia.
reset role;
select pg_temp.as_user(null);
delete from net.calls;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
insert into messages (id, channel_id, audio_path, duration_s)
  select '00000000-0000-0000-0000-0000000000c1', id, '00000000-0000-0000-0000-0000000000e1/voce.m4a', 30
  from channels where slug = 'main';
select pg_temp.expect_error(
  $q$insert into messages (channel_id, audio_path) select id, '00000000-0000-0000-0000-0000000000e1/x.m4a' from channels where slug = 'main'$q$,
  'messages_audio_duration_check');
select pg_temp.expect_error(
  $q$insert into messages (channel_id, audio_path, duration_s) select id, '00000000-0000-0000-0000-0000000000e1/x.m4a', 121 from channels where slug = 'main'$q$,
  'messages_voice_duration_check');
select pg_temp.expect_error(
  $q$insert into messages (channel_id, audio_path, duration_s, replay_path) select id, '00000000-0000-0000-0000-0000000000e1/x.m4a', 301, '00000000-0000-0000-0000-0000000000e1/x.json' from channels where slug = 'main'$q$,
  'messages_duration_s_check');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
insert into messages (channel_id, body, reply_to)
  select id, 'Bel vocale', '00000000-0000-0000-0000-0000000000c1' from channels where slug = 'main';
select pg_temp.expect_error(
  $q$insert into messages (channel_id, body, reply_to) select id, 'altro canale', '00000000-0000-0000-0000-0000000000c1' from channels where slug = 'milanac'$q$,
  'stesso canale');
insert into messages (channel_id, body, image_path, expires_at)
  select id, 'foto', '00000000-0000-0000-0000-0000000000e2/foto.jpg', now() + interval '10 years'
  from channels where slug = 'main';
do $$ begin
  assert (select expires_at between now() + interval '59 days' and now() + interval '61 days'
          from messages where id = '00000000-0000-0000-0000-0000000000c1'), 'il vocale scade dopo 60 giorni';
  assert (select expires_at between now() + interval '59 days' and now() + interval '61 days'
          from messages where body = 'foto'), 'anche la foto scade dopo 60 giorni (la scadenza non si sceglie)';
  assert (select expires_at is null from messages where body = 'Bel vocale'), 'il testo non scade';
  assert (select last_has_image and not last_has_audio from chat_overview()
          where channel_id = (select id from channels where slug = 'main')), 'riepilogo con foto e vocali';
end $$;
delete from messages where body = 'foto';
reset role;
select set_config('milanac.now', (now() + interval '61 days')::text, false);
do $$ begin
  assert (select count(*) from storage_cleanup where bucket = 'chat'
          and path = '00000000-0000-0000-0000-0000000000e2/foto.jpg') = 1, 'foto del messaggio eliminato in coda';
  assert expire_attachments() = 1, 'un allegato scaduto';
  assert (select audio_path is null and expired_at is not null and body is null
          from messages where id = '00000000-0000-0000-0000-0000000000c1'), 'il messaggio resta senza il vocale';
  assert (select count(*) from storage_cleanup) = 2, 'file in coda per la pulizia';
  assert (select count(*) from net.calls where body->>'kind' = 'cleanup') = 1, 'la pulizia dei file è stata chiesta';
  assert (select count(*) from cron.job where jobname = 'allegati-scaduti') = 1, 'pulizia notturna programmata';
end $$;
select set_config('milanac.now', '', false);

-- Carte speciali: il portiere viene dalla formazione pubblicata; la blu elettrico è automatica
-- (tripletta; tre partite ufficiali di fila senza subire gol); le nero/oro le assegna il Direttivo,
-- una per reparto, con l'annuncio in Comunicazioni.
reset role;
select pg_temp.as_user(null);
delete from net.calls;
update profiles set field_position = 'POR' where id = '00000000-0000-0000-0000-0000000000e2';
update profiles set field_position = 'DC' where id = '00000000-0000-0000-0000-0000000000e1';
update formation_slots set player_id = '00000000-0000-0000-0000-0000000000e2'
  where formation_id = '00000000-0000-0000-0000-0000000000f1' and slot_index = 0;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into matches (id, kind, opponent, played_at, team, goals_for, goals_against, scorers)
values ('00000000-0000-0000-0000-0000000000b3', 'torneo', 'Lupi', now() + interval '2 days', 'milanac', 4, 0, 'Rossi (3), e1');
update matches set scorers = 'Rossi (3), e1 (1)' where id = '00000000-0000-0000-0000-0000000000b3';
do $$ begin
  assert (select goalkeeper_id from matches where id = '00000000-0000-0000-0000-0000000000b3')
         = '00000000-0000-0000-0000-0000000000e2', 'portiere dalla formazione pubblicata';
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000b3'
          and kind = 'blu' and player_id = '00000000-0000-0000-0000-0000000000a1' and reparto = 'ATT'
          and bonus = 5 and reason = 'Tripletta contro Lupi') = 1, 'blu elettrico per la tripletta';
  assert (select count(*) from special_cards) = 1, 'una sola carta (la correzione dei marcatori non la raddoppia)';
  assert (select ends_at - starts_at from special_cards) = interval '7 days', 'la carta dura una settimana';
end $$;
-- Il giocatore legge le carte ma non le assegna.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error(
  $q$select assign_special_cards('00000000-0000-0000-0000-0000000000b3', '[]')$q$, 'Solo il Direttivo');
select pg_temp.expect_error(
  $q$insert into special_cards (player_id, kind, reparto) values ('00000000-0000-0000-0000-0000000000e1', 'nero_oro', 'DIF')$q$,
  'row-level security');
do $$ begin
  assert (select count(*) from special_cards) = 1, 'le carte si leggono';
end $$;
-- Il Direttivo assegna: reparto dalla posizione in campo, bonus da +1 a +5, un premiato per reparto.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select pg_temp.expect_error(
  $q$select assign_special_cards('00000000-0000-0000-0000-0000000000b3', '[{"player_id": "00000000-0000-0000-0000-00000000000c", "bonus": 5}]')$q$,
  'non è della squadra');
select pg_temp.expect_error(
  $q$select assign_special_cards('00000000-0000-0000-0000-0000000000b3', '[{"player_id": "00000000-0000-0000-0000-00000000000d", "bonus": 5}]')$q$,
  'Reparto sconosciuto');
select pg_temp.expect_error(
  $q$select assign_special_cards('00000000-0000-0000-0000-0000000000b3', '[{"player_id": "00000000-0000-0000-0000-0000000000e1", "bonus": 6}]')$q$,
  'bonus');
select pg_temp.expect_error(
  $q$select assign_special_cards('00000000-0000-0000-0000-0000000000b3', '[{"player_id": "00000000-0000-0000-0000-0000000000e1"}, {"player_id": "00000000-0000-0000-0000-0000000000e2", "reparto": "DIF"}]')$q$,
  'per reparto');
select pg_temp.expect_error(
  $q$select assign_special_cards((select id from matches where opponent = 'Dinamo' and goals_for is null), '[]')$q$,
  'prima il risultato');
do $$ begin
  assert assign_special_cards('00000000-0000-0000-0000-0000000000b3',
    '[{"player_id": "00000000-0000-0000-0000-0000000000e1", "bonus": 4},
      {"player_id": "00000000-0000-0000-0000-0000000000a1", "bonus": 5},
      {"player_id": "00000000-0000-0000-0000-0000000000e2"}]') = 2,
    'due carte nero/oro nuove (Rossi tiene la blu)';
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000b3' and kind = 'nero_oro') = 2,
    'nero/oro per portiere e difensore';
  assert (select body from messages where meta->>'type' = 'special_cards')
         like 'Carte speciali della _ª giornata (Milan AC 4–0 Lupi): POR e2 +5, DIF e1 +4. Blu elettrico: Rossi (tripletta contro Lupi).',
    'annuncio in Comunicazioni';
  -- Nuova assegnazione: chi non è più in elenco perde la carta, i bonus si aggiornano, l'annuncio resta uno.
  assert assign_special_cards('00000000-0000-0000-0000-0000000000b3',
    '[{"player_id": "00000000-0000-0000-0000-0000000000e1", "bonus": 2}]') = 0, 'nessuna carta nuova';
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000b3' and kind = 'nero_oro') = 1,
    'la carta del portiere è stata tolta';
  assert (select bonus from special_cards where player_id = '00000000-0000-0000-0000-0000000000e1') = 2, 'bonus aggiornato';
  assert (select count(*) from messages where meta->>'type' = 'special_cards') = 1, 'un solo annuncio per partita';
  assert (select body from messages where meta->>'type' = 'special_cards') like '%: DIF e1 +2. Blu elettrico: Rossi%',
    'annuncio aggiornato';
end $$;
-- Portiere: la terza partita ufficiale di fila senza subire gol vale la blu; le amichevoli non contano.
insert into matches (kind, opponent, played_at, team, goals_for, goals_against, goalkeeper_id)
values ('torneo', 'Orsi', now() + interval '3 days', 'milanac', 1, 0, '00000000-0000-0000-0000-0000000000e2');
do $$ begin
  assert (select count(*) from special_cards where player_id = '00000000-0000-0000-0000-0000000000e2' and kind = 'blu') = 0,
    'due partite senza subire gol non bastano';
end $$;
insert into matches (kind, opponent, played_at, team, goals_for, goals_against, goalkeeper_id)
values ('amichevole', 'Amici', now() + interval '3 days 1 hour', 'milanac', 3, 0, '00000000-0000-0000-0000-0000000000e2');
insert into matches (kind, opponent, played_at, team, goals_for, goals_against, goalkeeper_id)
values ('torneo', 'Aquile', now() + interval '4 days', 'milanac', 2, 0, '00000000-0000-0000-0000-0000000000e2');
do $$ begin
  assert (select count(*) from special_cards where player_id = '00000000-0000-0000-0000-0000000000e2' and kind = 'blu'
          and reparto = 'POR' and reason = 'Tre partite di fila senza subire gol') = 1, 'blu elettrico al portiere';
end $$;
reset role;
do $$ begin
  -- match_number non è più chiamabile dall'app: si controlla da amministratore.
  assert (select body from messages where meta->>'type' = 'special_cards')
         like 'Carte speciali della ' || match_number('00000000-0000-0000-0000-0000000000b3') || 'ª giornata%',
    'numero della giornata nell''annuncio';
  assert match_number('00000000-0000-0000-0000-0000000000b3') between 1 and 3, 'numero della giornata';
  assert (select count(*) from net.calls where body->>'kind' = 'special_card') = 4,
    'un avviso per ogni carta ricevuta (blu Rossi, nero/oro e1 ed e2, blu portiere)';
  assert (select count(*) from net.calls where body->>'kind' = 'special_cards_week') = 1,
    'avviso alla squadra solo quando arrivano carte nuove (non per un bonus corretto)';
  assert (select count(*) from net.calls where body->>'kind' = 'chat_message') = 0,
    'l''annuncio delle carte non manda l''avviso generico della chat';
  assert (select count(*) from net.calls where body->>'kind' = 'match_result') = 4, 'una notifica per ogni risultato';
end $$;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
do $$ begin
  assert (player_stats('00000000-0000-0000-0000-0000000000a1')->>'blu')::int = 1, 'carte blu nelle statistiche';
  assert (player_stats('00000000-0000-0000-0000-0000000000e1')->>'nero_oro')::int = 1, 'carte nero/oro nelle statistiche';
end $$;
reset role;

-- Tornei: la foto (o il logo) la carica solo il Direttivo, nella cartella del torneo.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into tournaments (id, name, team) values ('00000000-0000-0000-0000-0000000000a9', 'Coppa Rossonera', 'milanac');
insert into storage.objects (bucket_id, name) values ('tournaments', '00000000-0000-0000-0000-0000000000a9/logo.jpg');
update tournaments set image_path = '00000000-0000-0000-0000-0000000000a9/logo.jpg'
  where id = '00000000-0000-0000-0000-0000000000a9';
select pg_temp.expect_error(
  $q$update tournaments set image_path = 'altrove/logo.jpg' where id = '00000000-0000-0000-0000-0000000000a9'$q$,
  'tournaments_image_path_check');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error(
  $q$insert into storage.objects (bucket_id, name) values ('tournaments', '00000000-0000-0000-0000-0000000000a9/altra.jpg')$q$,
  'row-level security');
do $$ begin
  assert (select count(*) from storage.objects where bucket_id = 'tournaments') = 1, 'il membro vede la foto del torneo';
  assert (select image_path from tournaments where id = '00000000-0000-0000-0000-0000000000a9') like '%/logo.jpg', 'foto salvata';
end $$;
reset role;

-- Lavagna tattica: gli schemi con la lavagna li salva il Direttivo; il replay in chat dura
-- fino a 5 minuti (i vocali normali 2) e scade dopo 3 giorni.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into tactics (title, module, team, board)
values ('Uscita dal basso', '4-3-3', 'milanac', '{"module": "4-3-3", "tokens": [{"id": "k1", "x": 0.5, "y": 0.9}], "arrows": [], "heat": []}');
select pg_temp.expect_error(
  $q$insert into tactics (title, team) values ('X', 'primavera')$q$, 'tactics_team_check');
select pg_temp.expect_error(
  $q$insert into tactics (title, board) values ('X', '[1, 2]')$q$, 'tactics_board_check');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
update tactics set board = '{}' where title = 'Uscita dal basso';  -- ignorato dalle policy
do $$ begin
  assert (select board->>'module' from tactics where title = 'Uscita dal basso') = '4-3-3',
    'il giocatore legge la lavagna ma non la modifica';
end $$;
-- Replay: audio fino a 5 minuti più il file delle azioni; un vocale normale resta a 2 minuti.
select pg_temp.expect_error(
  $q$insert into messages (channel_id, audio_path, duration_s) select id, '00000000-0000-0000-0000-0000000000e1/v.m4a', 200 from channels where slug = 'tattiche'$q$,
  'messages_voice_duration_check');
insert into messages (id, channel_id, audio_path, duration_s, replay_path, meta)
  select '00000000-0000-0000-0000-0000000000c9', id, '00000000-0000-0000-0000-0000000000e1/replay.m4a', 200,
         '00000000-0000-0000-0000-0000000000e1/replay.json', '{"type": "replay", "title": "Uscita dal basso"}'
  from channels where slug = 'tattiche';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select expires_at between now() + interval '2 days 23 hours' and now() + interval '3 days 1 hour'
          from messages where id = '00000000-0000-0000-0000-0000000000c9'), 'il replay scade dopo 3 giorni';
  assert (select last_type from chat_overview() where channel_id = (select id from channels where slug = 'tattiche')) = 'replay',
    'il riepilogo dice che l''ultimo messaggio è un replay';
end $$;
reset role;
delete from net.calls;
select set_config('milanac.now', (now() + interval '4 days')::text, false);
do $$ begin
  assert expire_attachments() = 1, 'il replay scaduto';
  assert (select replay_path is null and audio_path is null and expired_at is not null
          from messages where id = '00000000-0000-0000-0000-0000000000c9'), 'il messaggio resta senza i file';
  assert (select count(*) from storage_cleanup where path like '%/replay.%') = 2, 'audio e azioni in coda';
end $$;
select set_config('milanac.now', '', false);

-- Stanza vocale: una per canale, avviso solo all'apertura, si chiude quando esce l'ultimo;
-- chi sparisce senza uscire viene fatto uscire dal controllo di pg_cron; minuti del mese.
reset role;
select pg_temp.as_user(null);
delete from net.calls;
select set_config('milanac.now', '', false);
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error(
  $q$select open_voice_room((select id from channels where slug = 'futuro'))$q$, 'non disponibile');
select set_config('test.stanza', open_voice_room((select id from channels where slug = 'main'))::text, false);
do $$ begin
  assert (select open_voice_room((select id from channels where slug = 'main'))::text) = current_setting('test.stanza'),
    'aprendo di nuovo si entra nella stessa stanza';
  assert (select count(*) from voice_sessions where left_at is null) = 1, 'una sessione attiva';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
select set_config('test.sessione_e2', join_voice_room(current_setting('test.stanza')::uuid, 12345)::text, false);
select voice_heartbeat(current_setting('test.sessione_e2')::uuid, true);
do $$ begin
  assert (select count(*) from voice_sessions where room_id = current_setting('test.stanza')::uuid and left_at is null) = 2,
    'due dentro';
  assert (select muted from voice_sessions where id = current_setting('test.sessione_e2')::uuid), 'muto registrato';
  assert (select agora_uid from voice_sessions where id = current_setting('test.sessione_e2')::uuid) = 1428969133,
    'uid Agora calcolato dal server (lo stesso dell''app), non quello passato';
end $$;
select leave_voice_room(current_setting('test.sessione_e2')::uuid);
do $$ begin
  assert (select closed_at is null from voice_rooms where id = current_setting('test.stanza')::uuid),
    'la stanza resta aperta finché c''è qualcuno';
end $$;
reset role;
do $$ begin
  assert (select count(*) from net.calls where body->>'kind' = 'voice_room') = 1, 'un solo avviso di stanza aperta';
  assert (select count(*) from cron.job where jobname = 'stanze-vocali') = 1, 'controllo delle stanze ogni minuto';
end $$;
-- Dieci minuti dopo e1 non ha più dato segni di vita: esce d'ufficio e la stanza si chiude.
select set_config('milanac.now', (now() + interval '10 minutes')::text, false);
select voice_tick();
do $$ begin
  assert (select count(*) from voice_sessions where left_at is null) = 0, 'sessione abbandonata chiusa';
  assert (select closed_at is not null from voice_rooms where id = current_setting('test.stanza')::uuid), 'stanza chiusa';
end $$;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert voice_minutes() between 1 and 11, 'minuti del mese contati';
  assert voice_minutes(date '2001-01-01') = 0, 'nessun minuto in un altro mese';
end $$;
select pg_temp.expect_error(
  $q$select join_voice_room(current_setting('test.stanza')::uuid)$q$, 'chiusa');
reset role;
select set_config('milanac.now', '', false);

-- ---------------------------------------------------------------- regolamento d'ingresso (0021)
-- Chi pubblica una versione la ha già accettata (la 2 l'ha pubblicata a2).
reset role;
do $$ begin
  assert (select rules_accepted_version from profiles where id = '00000000-0000-0000-0000-0000000000a2') = 2,
    'chi pubblica ha già accettato la versione';
end $$;
-- Con una versione pubblicata non si entra senza accettarla.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.expect_error($q$select enter_club()$q$, 'regolamento da accettare');
reset role;
-- Senza nessuna versione: si entra con il ruolo richiesto, poi il primo del Direttivo pubblica.
begin;
delete from rules_versions;
update app_config set value = crypt('prova-test', gen_salt('bf')) where key = 'direttivo_password_hash';
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a3', 'r3@example.com');
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select pg_temp.expect_error($q$select enter_club()$q$, 'Completa prima');
select complete_registration('Gigi', 'Verdi', 1999, 'VERDI', null, array['milanac'], true, 'prova-test', array['capitano'], 'CC', 8, 'ps5', '{}');
select enter_club();
do $$ begin
  assert (select club_role from profiles where id = '00000000-0000-0000-0000-0000000000a3') = 'direttivo',
    'senza regolamento si entra con il ruolo richiesto';
  assert (select rules_accepted_version from profiles where id = '00000000-0000-0000-0000-0000000000a3') is null,
    'nessuna versione accettata';
end $$;
select enter_club();  -- ripetibile
insert into rules_articles (sort_order, title, body) values (0, 'Art. 1 – Ingresso', 'Benvenuto nel club.');
do $$ begin
  assert (select publish_rules()) = 1, 'prima versione';
  assert (select rules_accepted_version from profiles where id = '00000000-0000-0000-0000-0000000000a3') = 1,
    'chi pubblica la prima versione la ha accettata';
end $$;
select pg_temp.expect_error($q$select enter_club()$q$, 'regolamento da accettare');
reset role;
rollback;

-- ---------------------------------------------------------------- sicurezza (0022)
reset role;
select pg_temp.as_user(null);
select set_config('milanac.now', '', false);
update app_config set value = crypt('prova-test', gen_salt('bf')) where key = 'direttivo_password_hash';
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'f1@example.com'),
  ('00000000-0000-0000-0000-0000000000f2', 'f2@example.com');
-- f1 è nel Direttivo, poi viene rimosso (active = false): perde subito i poteri.
update profiles set club_role = 'direttivo' where id = '00000000-0000-0000-0000-0000000000f1';
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
do $$ begin
  assert is_direttivo(), 'Direttivo attivo';
end $$;
reset role;
update profiles set active = false where id = '00000000-0000-0000-0000-0000000000f1';
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
do $$ begin
  assert not is_direttivo(), 'il Direttivo rimosso non ha più poteri';
end $$;
select pg_temp.expect_error(
  $q$insert into matches (kind, opponent, played_at) values ('amichevole', 'Intrusi', now())$q$,
  'row-level security');
select pg_temp.expect_error(
  $q$update profiles set active = true where id = '00000000-0000-0000-0000-0000000000f1'$q$,
  'Solo il Direttivo');

-- Password del Direttivo: 5 tentativi sbagliati ogni 15 minuti, poi blocco (anche con quella giusta).
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
do $$
declare i int;
begin
  for i in 1..5 loop
    assert (select complete_registration('Ugo', 'Neri', 1990, 'NERI', null, array['milanac'], true, 'tentativo', array['capitano'], 'CC', 7, 'ps5', '{}'))
           = 'password_errata', 'tentativo sbagliato';
  end loop;
end $$;
select pg_temp.expect_error(
  $q$select complete_registration('Ugo', 'Neri', 1990, 'NERI', null, array['milanac'], true, 'prova-test', array['capitano'], 'CC', 7, 'ps5', '{}')$q$,
  'Troppi tentativi');
reset role;
do $$ begin
  assert (select count(*) from direttivo_password_attempts
          where user_id = '00000000-0000-0000-0000-0000000000f2') = 5, 'tentativi registrati';
end $$;
delete from direttivo_password_attempts;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
do $$ begin
  assert (select complete_registration('Ugo', 'Neri', 1990, 'NERI', null, array['milanac'], true, 'prova-test', array['capitano'], 'CC', 7, 'ps5', '{}'))
         = 'ok', 'con la password giusta si completa';
end $$;
-- Chi è già nel club non ripassa dalla registrazione (squadre e ruolo li cambia il Direttivo).
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.expect_error(
  $q$select complete_registration('Mario', 'Rossi', 1995, 'ROSSI', null, array['futuro'], false, null, null, 'ATT', 9, 'ps5', '{}')$q$,
  'già nel club');
-- Il primo Direttivo nominato dall'editor SQL prima di registrarsi completa la registrazione
-- (una volta sola) e resta Direttivo.
reset role;
select pg_temp.as_user(null);
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a8', 'primo@example.com');
update profiles set club_role = 'direttivo' where id = '00000000-0000-0000-0000-0000000000a8';
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a8');
do $$ begin
  assert (select complete_registration('Primo', 'Capo', 1985, 'CAPO', null, array['milanac'], false, null, null, 'CC', 8, 'ps5', '{}'))
         = 'ok', 'il primo Direttivo completa la registrazione';
  assert (select club_role from profiles where id = '00000000-0000-0000-0000-0000000000a8') = 'direttivo',
    'e resta Direttivo';
end $$;
select pg_temp.expect_error(
  $q$select complete_registration('Primo', 'Capo', 1985, 'CAPO', null, array['futuro'], false, null, null, 'CC', 8, 'ps5', '{}')$q$,
  'già nel club');
-- Il permesso della registrazione vale per un solo aggiornamento del profilo:
-- il primo passa, il secondo nella stessa transazione no.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select pg_temp.expect_error(
  $q$do $d$ begin
       perform set_config('milanac.registration', '1', true);
       update profiles set overall = 98 where id = '00000000-0000-0000-0000-0000000000f2';
       update profiles set overall = 99 where id = '00000000-0000-0000-0000-0000000000f2';
     end $d$$q$,
  'Solo il Direttivo');

-- Allegati: solo dalla propria cartella; i file della Sala Direttivo li legge solo chi vede il canale.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error(
  $q$insert into messages (channel_id, image_path) select id, '00000000-0000-0000-0000-0000000000e2/foto.jpg' from channels where slug = 'main'$q$,
  'Allegato non valido');
reset role;
insert into storage.objects (bucket_id, name) values
  ('chat', '00000000-0000-0000-0000-00000000000d/segreto.jpg'),
  ('chat', '00000000-0000-0000-0000-0000000000e2/vocale.m4a');
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into messages (channel_id, image_path)
  select id, '00000000-0000-0000-0000-00000000000d/segreto.jpg' from channels where slug = 'direttivo';
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
insert into messages (channel_id, audio_path, duration_s)
  select id, '00000000-0000-0000-0000-0000000000e2/vocale.m4a', 12 from channels where slug = 'main';
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
do $$ begin
  assert (select count(*) from storage.objects
          where name = '00000000-0000-0000-0000-00000000000d/segreto.jpg') = 0,
    'il file della Sala Direttivo non si legge';
  assert (select count(*) from storage.objects
          where name = '00000000-0000-0000-0000-0000000000e2/vocale.m4a') = 1,
    'il vocale del canale generale sì';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select count(*) from storage.objects
          where name = '00000000-0000-0000-0000-00000000000d/segreto.jpg') = 1,
    'il Direttivo legge i suoi allegati';
end $$;

-- Marcatori: il nome sulla carta vale più del gamertag copiato; un nome ambiguo non assegna gol.
reset role;
update profiles set display_name = 'VERDI', gamertag = null, teams = array['milanac'], active = true
  where id = '00000000-0000-0000-0000-0000000000e1';
update profiles set gamertag = 'verdi', teams = array['milanac'], active = true
  where id = '00000000-0000-0000-0000-0000000000e2';
do $$ begin
  assert (select count(*) from scorer_goals('Verdi 3', 'milanac')) = 1, 'un solo marcatore';
  assert (select player_id from scorer_goals('Verdi 3', 'milanac')) = '00000000-0000-0000-0000-0000000000e1',
    'conta il nome sulla carta';
  assert (select goals from scorer_goals('Verdi 3', 'milanac')) = 3, 'tre gol';
end $$;
update profiles set display_name = 'VERDI' where id = '00000000-0000-0000-0000-0000000000e2';
do $$ begin
  assert (select count(*) from scorer_goals('Verdi 3', 'milanac')) = 0, 'due carte uguali: nessun gol assegnato';
end $$;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error($q$select * from scorer_goals('Verdi', 'milanac')$q$, 'permission denied');

-- Token del telefono: passa all'account che lo registra.
select register_device_token('token-condiviso', 'android');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
select register_device_token('token-condiviso', 'android');
reset role;
do $$ begin
  assert (select user_id from device_tokens where token = 'token-condiviso') = '00000000-0000-0000-0000-0000000000e2',
    'il token segue l''account attuale';
  assert agora_uid_for('00000000-0000-0000-0000-00000000000d') = 1428967540, 'stesso numero Agora dell''app';
end $$;

-- Eliminazione dell'account: le foto vanno nella coda di pulizia.
insert into storage.objects (bucket_id, name) values ('avatars', '00000000-0000-0000-0000-0000000000f2/foto.jpg');
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select delete_my_account();
reset role;
do $$ begin
  assert (select count(*) from profiles where id = '00000000-0000-0000-0000-0000000000f2') = 0, 'account eliminato';
  assert (select count(*) from storage_cleanup
          where bucket = 'avatars' and path = '00000000-0000-0000-0000-0000000000f2/foto.jpg') = 1,
    'foto in coda per la pulizia';
end $$;

-- ================================================================ affidabilità (0023)
reset role;
select pg_temp.as_user(null);
select set_config('milanac.now', '', false);
do $$ begin
  assert (select count(*) from pg_publication_tables where pubname = 'supabase_realtime'
          and tablename in ('matches', 'match_media', 'tournaments', 'tactics', 'channels')) = 5,
    'tempo reale per partite, foto e video, tornei, schemi e canali';
end $$;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a9', 'b@example.com');
update profiles set club_role = 'giocatore', display_name = 'GIALLI', teams = array['milanac'],
  field_position = 'ATT', active = true
  where id = '00000000-0000-0000-0000-0000000000a9';

-- Carte nero/oro: due giocatori si scambiano il reparto; un giocatore riceve una sola carta.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select assign_special_cards('00000000-0000-0000-0000-0000000000b3',
  '[{"player_id": "00000000-0000-0000-0000-0000000000e1", "reparto": "DIF"},
    {"player_id": "00000000-0000-0000-0000-0000000000e2", "reparto": "CEN"}]');
select assign_special_cards('00000000-0000-0000-0000-0000000000b3',
  '[{"player_id": "00000000-0000-0000-0000-0000000000e1", "reparto": "CEN"},
    {"player_id": "00000000-0000-0000-0000-0000000000e2", "reparto": "DIF"}]');
do $$ begin
  assert (select reparto from special_cards where match_id = '00000000-0000-0000-0000-0000000000b3'
          and kind = 'nero_oro' and player_id = '00000000-0000-0000-0000-0000000000e1') = 'CEN', 'reparti scambiati (e1)';
  assert (select reparto from special_cards where match_id = '00000000-0000-0000-0000-0000000000b3'
          and kind = 'nero_oro' and player_id = '00000000-0000-0000-0000-0000000000e2') = 'DIF', 'reparti scambiati (e2)';
end $$;
select pg_temp.expect_error(
  $q$select assign_special_cards('00000000-0000-0000-0000-0000000000b3',
    '[{"player_id": "00000000-0000-0000-0000-0000000000e1", "reparto": "DIF"},
      {"player_id": "00000000-0000-0000-0000-0000000000e1", "reparto": "CEN"}]')$q$,
  'una sola carta');

-- Carte blu: una correzione dei marcatori che toglie la tripletta toglie anche la carta.
insert into matches (id, kind, opponent, played_at, team, goals_for, goals_against, scorers)
values ('00000000-0000-0000-0000-0000000000b9', 'amichevole', 'Prova', now() + interval '5 days',
        'milanac', 4, 1, 'Gialli 3, Verdi');
do $$ begin
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000b9'
          and kind = 'blu' and player_id = '00000000-0000-0000-0000-0000000000a9') = 1, 'tripletta: carta blu';
end $$;
update matches set scorers = 'Gialli 2, Verdi 2' where id = '00000000-0000-0000-0000-0000000000b9';
do $$ begin
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000b9'
          and kind = 'blu') = 0, 'niente più tripletta: carta blu tolta';
end $$;
update matches set scorers = 'Gialli x3' where id = '00000000-0000-0000-0000-0000000000b9';
update matches set goals_for = null, goals_against = null where id = '00000000-0000-0000-0000-0000000000b9';
do $$ begin
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000b9') = 0,
    'risultato tolto: carta blu tolta';
end $$;

-- Giornata: due partite ufficiali alla stessa ora contano nell'ordine di inserimento.
insert into matches (id, kind, opponent, played_at, team, goals_for, goals_against)
values ('00000000-0000-0000-0000-0000000000c1', 'torneo', 'Alfa', date_trunc('day', now()) + interval '6 days 21 hours 30 minutes',
        'milanac', 2, 1);
insert into matches (id, kind, opponent, played_at, team, goals_for, goals_against)
values ('00000000-0000-0000-0000-0000000000c0', 'torneo', 'Beta', date_trunc('day', now()) + interval '6 days 21 hours 30 minutes',
        'milanac', 1, 1);
reset role;
do $$ begin
  assert match_number('00000000-0000-0000-0000-0000000000c1') + 1 = match_number('00000000-0000-0000-0000-0000000000c0'),
    'a parità di orario vale l''ordine di inserimento';
end $$;

-- Serie del portiere: correggere una partita ricontrolla le due successive.
update profiles set field_position = 'POR' where id = '00000000-0000-0000-0000-0000000000a9';
insert into matches (id, kind, opponent, played_at, team, goals_for, goals_against, goalkeeper_id, created_at) values
  ('00000000-0000-0000-0000-0000000000d1', 'torneo', 'Uno', now() + interval '20 days', 'milanac', 1, 0, '00000000-0000-0000-0000-0000000000a9', now()),
  ('00000000-0000-0000-0000-0000000000d2', 'torneo', 'Due', now() + interval '21 days', 'milanac', 1, 0, '00000000-0000-0000-0000-0000000000a9', now()),
  ('00000000-0000-0000-0000-0000000000d3', 'torneo', 'Tre', now() + interval '22 days', 'milanac', 1, 0, '00000000-0000-0000-0000-0000000000a9', now());
do $$ begin
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000d3'
          and kind = 'blu' and player_id = '00000000-0000-0000-0000-0000000000a9') = 1, 'tre porte inviolate: carta blu';
end $$;
update matches set goals_against = 2 where id = '00000000-0000-0000-0000-0000000000d1';
do $$ begin
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000d3'
          and kind = 'blu') = 0, 'la prima partita ha subito gol: la carta della terza cade';
end $$;

-- Traguardi: le risposte per i giorni futuri non contano.
insert into attendance (player_id, date, status) values
  ('00000000-0000-0000-0000-0000000000a9', (now() at time zone 'Europe/Rome')::date + 1, 'presente'),
  ('00000000-0000-0000-0000-0000000000a9', (now() at time zone 'Europe/Rome')::date + 2, 'presente');
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a9');
do $$ begin
  assert (player_stats('00000000-0000-0000-0000-0000000000a9')->>'presences')::int = 0,
    'le presenze future non contano';
end $$;

-- Formazione: salvata in un colpo solo, solo dal Direttivo.
select pg_temp.expect_error(
  $q$select save_formation(null, 'futuro', '4-4-2', '[]')$q$, 'Solo il Direttivo');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select set_config('test.formazione', save_formation(null, 'futuro', '4-4-2',
  '[{"slot_index": 0, "x": 0.5, "y": 0.9, "label": "POR", "player_id": "00000000-0000-0000-0000-0000000000e2"},
    {"slot_index": 1, "x": 0.2, "y": 0.7, "label": "TS", "player_id": null}]')::text, false);
do $$ begin
  assert (select count(*) from formation_slots where formation_id = current_setting('test.formazione')::uuid) = 2,
    'posti salvati';
  assert save_formation(current_setting('test.formazione')::uuid, 'futuro', '3-5-2',
    '[{"slot_index": 0, "x": 0.5, "y": 0.9, "label": "POR", "player_id": null}]') = current_setting('test.formazione')::uuid,
    'stessa formazione aggiornata';
  assert (select count(*) from formation_slots where formation_id = current_setting('test.formazione')::uuid) = 1,
    'i posti si sostituiscono';
  assert (select module from formations where id = current_setting('test.formazione')::uuid) = '3-5-2', 'modulo aggiornato';
end $$;
select pg_temp.expect_error(
  $q$select save_formation(null, 'futuro', '4-4-2', '[{"slot_index": 0, "x": 0.5, "y": 0.9, "label": "POR", "player_id": "non-un-id"}]')$q$,
  'uuid');

-- Stanza vocale: una stanza per volta; il segno di vita dice se si è ancora dentro.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select set_config('test.stanza_a', open_voice_room((select id from channels where slug = 'main'))::text, false);
select set_config('test.sessione_a', (select id from voice_sessions
  where room_id = current_setting('test.stanza_a')::uuid and left_at is null)::text, false);
select set_config('test.stanza_b', open_voice_room((select id from channels where slug = 'milanac'))::text, false);
do $$ begin
  assert current_setting('test.stanza_a') <> current_setting('test.stanza_b'), 'due stanze diverse';
  assert (select count(*) from voice_sessions
          where user_id = '00000000-0000-0000-0000-0000000000e1' and left_at is null) = 1,
    'entrando in un''altra stanza si esce dalla prima';
  assert (select closed_at is not null from voice_rooms where id = current_setting('test.stanza_a')::uuid),
    'la prima stanza, rimasta vuota, si chiude';
  assert voice_heartbeat(current_setting('test.sessione_a')::uuid) = false, 'sessione chiusa: il segno di vita lo dice';
end $$;
select leave_voice_room((select id from voice_sessions
  where user_id = '00000000-0000-0000-0000-0000000000e1' and left_at is null));
-- Finiti i 10.000 minuti gratuiti del mese non si entra più.
reset role;
insert into voice_sessions (room_id, user_id, joined_at, heartbeat_at, left_at)
select current_setting('test.stanza_a')::uuid, '00000000-0000-0000-0000-0000000000e2', t, t, t + interval '10000 minutes'
from (select (date_trunc('month', now() at time zone 'Europe/Rome') at time zone 'Europe/Rome') as t) x;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error(
  $q$select open_voice_room((select id from channels where slug = 'main'))$q$, 'minuti gratuiti');
reset role;
delete from voice_sessions where left_at - joined_at = interval '10000 minutes';
do $$ begin
  assert (select count(*) from voice_rooms where closed_at is null) = 0, 'nessuna stanza aperta per errore';
end $$;

-- Chat: "letto fino a" con l'ora del server, mai nel futuro e mai all'indietro.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select mark_channel_read((select id from channels where slug = 'main'), now() + interval '1 day');
do $$ begin
  assert (select last_read_at from channel_reads where user_id = '00000000-0000-0000-0000-0000000000e1'
          and channel_id = (select id from channels where slug = 'main')) <= now(), 'mai oltre adesso';
end $$;
select mark_channel_read((select id from channels where slug = 'main'), now() - interval '1 day');
do $$ begin
  assert (select last_read_at from channel_reads where user_id = '00000000-0000-0000-0000-0000000000e1'
          and channel_id = (select id from channels where slug = 'main')) > now() - interval '1 hour',
    'mai all''indietro';
end $$;
select mark_channel_read((select id from channels where slug = 'direttivo'), now());
do $$ begin
  assert (select count(*) from channel_reads where user_id = '00000000-0000-0000-0000-0000000000e1'
          and channel_id = (select id from channels where slug = 'direttivo')) = 0,
    'niente "letto" sui canali che non si vedono';
end $$;
reset role;

-- ================================================================ preferenze notifiche (0024)
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
update profiles set notify_prefs = '{"chat": false}' where id = '00000000-0000-0000-0000-0000000000e1';
do $$ begin
  assert (select notify_prefs->>'chat' from profiles where id = '00000000-0000-0000-0000-0000000000e1') = 'false',
    'ognuno sceglie le proprie notifiche';
end $$;
select pg_temp.expect_error(
  $q$update profiles set notify_prefs = '[]' where id = '00000000-0000-0000-0000-0000000000e1'$q$,
  'notify_prefs');
-- Le preferenze degli altri non si toccano.
update profiles set notify_prefs = '{"chat": false}' where id = '00000000-0000-0000-0000-0000000000e2';
reset role;
do $$ begin
  assert (select notify_prefs from profiles where id = '00000000-0000-0000-0000-0000000000e2') = '{}'::jsonb,
    'preferenze altrui invariate';
end $$;

-- ================================================================ rifiniture (0025)
-- Partita eliminata: via le sue carte speciali e il loro annuncio; la serie del portiere si
-- ricontrolla sulle partite successive.
update matches set goals_against = 0 where id = '00000000-0000-0000-0000-0000000000d1';
do $$ begin
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000d3'
          and kind = 'blu' and player_id = '00000000-0000-0000-0000-0000000000a9') = 1,
    'di nuovo tre porte inviolate: torna la blu';
end $$;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select assign_special_cards('00000000-0000-0000-0000-0000000000d2',
  '[{"player_id": "00000000-0000-0000-0000-0000000000e1", "reparto": "DIF"}]');
do $$ begin
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000d2') = 1,
    'carta nero/oro della partita';
  assert (select count(*) from messages where meta->>'type' = 'special_cards'
          and meta->>'match' = '00000000-0000-0000-0000-0000000000d2') = 1, 'annuncio della partita';
end $$;
delete from matches where id = '00000000-0000-0000-0000-0000000000d2';
do $$ begin
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000d2') = 0,
    'partita eliminata: via le sue carte';
  assert (select count(*) from messages where meta->>'type' = 'special_cards'
          and meta->>'match' = '00000000-0000-0000-0000-0000000000d2') = 0, 'e il loro annuncio';
end $$;
reset role;
do $$ begin
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000d3'
          and kind = 'blu') = 0, 'senza la partita eliminata la serie del portiere non c''è più';
  assert (select count(*) from special_cards where match_id is null) = 0, 'nessuna carta senza partita';
end $$;

-- La blu ha la precedenza anche quando arriva dopo: chi ha la nero/oro e poi fa tripletta
-- tiene solo la blu.
update matches set goals_for = 4, goals_against = 1, scorers = 'Gialli 2'
  where id = '00000000-0000-0000-0000-0000000000b9';
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select assign_special_cards('00000000-0000-0000-0000-0000000000b9',
  '[{"player_id": "00000000-0000-0000-0000-0000000000a9"}]');
reset role;
do $$ begin
  assert (select kind from special_cards where match_id = '00000000-0000-0000-0000-0000000000b9'
          and player_id = '00000000-0000-0000-0000-0000000000a9') = 'nero_oro', 'prima la nero/oro';
end $$;
update matches set scorers = 'Gialli 3, Verdi' where id = '00000000-0000-0000-0000-0000000000b9';
do $$ begin
  assert (select string_agg(kind, ',') from special_cards where match_id = '00000000-0000-0000-0000-0000000000b9'
          and player_id = '00000000-0000-0000-0000-0000000000a9') = 'blu', 'poi la tripletta: resta solo la blu';
  assert (select body from messages where meta->>'type' = 'special_cards'
          and meta->>'match' = '00000000-0000-0000-0000-0000000000b9') like '%Blu elettrico: GIALLI%',
    'annuncio aggiornato con la blu';
end $$;

-- Carte nero/oro: chi cambia reparto tiene la sua carta (stesse date, nessun nuovo avviso).
reset role;
update special_cards set starts_at = now() - interval '2 days', ends_at = now() + interval '5 days'
  where match_id = '00000000-0000-0000-0000-0000000000b3' and kind = 'nero_oro';
select set_config('test.carta_e1', (select id::text from special_cards
  where match_id = '00000000-0000-0000-0000-0000000000b3' and kind = 'nero_oro'
    and player_id = '00000000-0000-0000-0000-0000000000e1'), false);
delete from net.calls;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select assign_special_cards('00000000-0000-0000-0000-0000000000b3',
  '[{"player_id": "00000000-0000-0000-0000-0000000000e1", "reparto": "DIF"},
    {"player_id": "00000000-0000-0000-0000-0000000000e2", "reparto": "CEN", "bonus": 3}]');
reset role;
do $$ begin
  assert (select reparto from special_cards where match_id = '00000000-0000-0000-0000-0000000000b3'
          and kind = 'nero_oro' and player_id = '00000000-0000-0000-0000-0000000000e1') = 'DIF', 'reparto cambiato';
  assert (select id::text from special_cards where match_id = '00000000-0000-0000-0000-0000000000b3'
          and kind = 'nero_oro' and player_id = '00000000-0000-0000-0000-0000000000e1')
         = current_setting('test.carta_e1'), 'stessa carta (l''app non la festeggia di nuovo)';
  assert (select count(*) from special_cards where match_id = '00000000-0000-0000-0000-0000000000b3'
          and kind = 'nero_oro' and starts_at < now() - interval '1 day') = 2, 'stesse date di prima';
  assert (select bonus from special_cards where match_id = '00000000-0000-0000-0000-0000000000b3'
          and kind = 'nero_oro' and player_id = '00000000-0000-0000-0000-0000000000e2') = 3, 'bonus corretto';
  assert (select count(*) from net.calls where body->>'kind' in ('special_card', 'special_cards_week')) = 0,
    'nessun nuovo avviso per un cambio di reparto o di bonus';
end $$;

-- Formazione: ora di pubblicazione dal server; il portiere viene dalla formazione pubblicata.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select save_formation(current_setting('test.formazione')::uuid, 'futuro', '4-4-2',
  '[{"slot_index": 0, "x": 0.5, "y": 0.9, "label": "POR", "player_id": "00000000-0000-0000-0000-0000000000e2"},
    {"slot_index": 1, "x": 0.2, "y": 0.7, "label": "TS", "player_id": "00000000-0000-0000-0000-0000000000f1"},
    {"slot_index": 2, "x": 0.4, "y": 0.7, "label": "DC", "player_id": "00000000-0000-0000-0000-0000000000e1"}]');
update formations set published_at = '2001-01-01', published_module = '4-4-2',
  published_players = '{"0": "00000000-0000-0000-0000-0000000000e2", "1": "00000000-0000-0000-0000-0000000000f1",
                        "2": "00000000-0000-0000-0000-0000000000e1"}'
  where id = current_setting('test.formazione')::uuid;
reset role;
do $$ begin
  assert (select published_at from formations where id = current_setting('test.formazione')::uuid)
         > now() - interval '1 hour', 'ora di pubblicazione dal server, non dal telefono';
  assert (select body from messages where meta->>'type' = 'formation'
          and meta->>'id' = current_setting('test.formazione')
          order by created_at desc limit 1) like 'Formazione Milan AC Futuro (4-4-2): POR VERDI, DC %',
    'annuncio con i soli giocatori attivi (f1 è uscito dal club)';
end $$;
-- La bozza cambia portiere senza pubblicare: il risultato prende quello pubblicato.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select save_formation(current_setting('test.formazione')::uuid, 'futuro', '4-4-2',
  '[{"slot_index": 0, "x": 0.5, "y": 0.9, "label": "POR", "player_id": "00000000-0000-0000-0000-0000000000a9"}]');
insert into matches (id, kind, opponent, played_at, team, goals_for, goals_against)
values ('00000000-0000-0000-0000-0000000000d7', 'amichevole', 'Gatti', now() + interval '30 days', 'futuro', 1, 0);
do $$ begin
  assert (select goalkeeper_id from matches where id = '00000000-0000-0000-0000-0000000000d7')
         = '00000000-0000-0000-0000-0000000000e2', 'portiere della formazione pubblicata, non della bozza';
end $$;
-- Scegliere di nuovo "dalla formazione" (portiere vuoto) lo ricalcola.
update matches set goalkeeper_id = '00000000-0000-0000-0000-0000000000a9' where id = '00000000-0000-0000-0000-0000000000d7';
update matches set goalkeeper_id = null where id = '00000000-0000-0000-0000-0000000000d7';
do $$ begin
  assert (select goalkeeper_id from matches where id = '00000000-0000-0000-0000-0000000000d7')
         = '00000000-0000-0000-0000-0000000000e2', 'portiere ricalcolato dalla formazione';
end $$;
-- Posto del portiere vuoto nella formazione pubblicata: nessun portiere (non quello della bozza).
update formations set published_at = now() + interval '1 second',
  published_players = '{"1": "00000000-0000-0000-0000-0000000000e1"}'
  where id = current_setting('test.formazione')::uuid;
insert into matches (id, kind, opponent, played_at, team, goals_for, goals_against)
values ('00000000-0000-0000-0000-0000000000d8', 'amichevole', 'Volpi', now() + interval '31 days', 'futuro', 2, 0);
do $$ begin
  assert (select goalkeeper_id from matches where id = '00000000-0000-0000-0000-0000000000d8') is null,
    'nessun portiere se nella formazione pubblicata il posto era vuoto';
end $$;

-- Classifica dei tornei e contatti social: solo il Direttivo, in una transazione.
reset role;
insert into tournaments (id, name, team) values ('00000000-0000-0000-0000-0000000000aa', 'Coppa di prova', 'milanac');
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error(
  $q$select save_standings('00000000-0000-0000-0000-0000000000aa', '[]')$q$, 'Solo il Direttivo');
select pg_temp.expect_error($q$select save_club_links('[]')$q$, 'Solo il Direttivo');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select save_standings('00000000-0000-0000-0000-0000000000aa',
  '[{"team_name": " Milan AC ", "won": 3, "drawn": 1, "goals_for": 9, "goals_against": 2, "is_us": true},
    {"team_name": "Rivali", "lost": 2}]');
do $$ begin
  assert (select count(*) from tournament_standings where tournament_id = '00000000-0000-0000-0000-0000000000aa') = 2,
    'classifica salvata';
  assert (select won from tournament_standings where tournament_id = '00000000-0000-0000-0000-0000000000aa'
          and team_name = 'Milan AC' and is_us) = 3, 'righe complete';
end $$;
select save_standings('00000000-0000-0000-0000-0000000000aa', '[{"team_name": "Rivali", "won": 1}]');
select pg_temp.expect_error(
  $q$select save_standings('00000000-0000-0000-0000-0000000000aa', '[{"team_name": ""}]')$q$,
  'tournament_standings_team_name_check');
do $$ begin
  assert (select count(*) from tournament_standings where tournament_id = '00000000-0000-0000-0000-0000000000aa') = 1,
    'la classifica nuova sostituisce la vecchia; un errore non tocca niente';
end $$;
select save_club_links('[{"kind": "instagram", "url": "https://instagram.com/milanac"},
                         {"kind": "sito", "url": "https://milanac.example"}]');
select pg_temp.expect_error($q$select save_club_links('[{"kind": "sito", "url": "ftp://x"}]')$q$, 'Link non valido');
do $$ begin
  assert (select string_agg(kind || sort_order, ',' order by sort_order) from club_links) = 'instagram0,sito1',
    'contatti salvati nell''ordine; un errore non tocca niente';
end $$;
reset role;

-- Dati anagrafici: li vedono e li cambiano solo l'interessato e il Direttivo.
do $$ begin
  assert not exists (select 1 from information_schema.columns where table_schema = 'public'
                     and table_name = 'profiles' and column_name in ('first_name', 'last_name', 'birth_year', 'birth_date')),
    'nome, cognome e nascita non sono più in profiles';
  assert (select first_name || ' ' || last_name || ' ' || birth_year from profile_private
          where id = '00000000-0000-0000-0000-0000000000a1') = 'Mario Rossi 1995', 'la registrazione li salva a parte';
end $$;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
do $$ begin
  assert (select count(*) from profile_private) = 1, 'un giocatore vede solo i propri';
end $$;
update profile_private set first_name = 'Marione' where id = '00000000-0000-0000-0000-0000000000a1';
update profile_private set first_name = 'Hacker' where id = '00000000-0000-0000-0000-0000000000a2';
select pg_temp.expect_error(
  $q$insert into profile_private (id, first_name) values ('00000000-0000-0000-0000-0000000000e1', 'Hacker')$q$,
  'row-level security');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select count(*) from profile_private) >= 2, 'il Direttivo li vede tutti';
end $$;
insert into profile_private (id, first_name, last_name) values ('00000000-0000-0000-0000-0000000000e1', 'Enzo', 'Verdi');
reset role;
do $$ begin
  assert (select first_name from profile_private where id = '00000000-0000-0000-0000-0000000000a1') = 'Marione',
    'ognuno cambia i propri';
  assert (select first_name from profile_private where id = '00000000-0000-0000-0000-0000000000a2') = 'Fabio',
    'non quelli degli altri';
  assert (select first_name from profile_private where id = '00000000-0000-0000-0000-0000000000e1') = 'Enzo',
    'il Direttivo li completa';
  assert (select count(*) from pg_publication_tables where pubname = 'supabase_realtime'
          and tablename in ('tournament_standings', 'news', 'club_links', 'rules_versions', 'profile_private')) = 5,
    'tempo reale per classifiche, notizie, contatti, regolamento e dati anagrafici';
end $$;
set role anon;
select pg_temp.expect_error($q$select count(*) from profile_private$q$, 'permission denied');
reset role;

-- Nuovo ingresso: il Direttivo lo sa dalla Sala Direttivo; gli altri non vedono l'avviso.
do $$ begin
  assert (select body from messages where meta->>'type' = 'new_member'
          and meta->>'member' = '00000000-0000-0000-0000-0000000000a1')
         like 'Nuovo ingresso: Rossi (Mario Rossi) · Giocatore · Milan AC · ATT.%', 'avviso del nuovo ingresso';
  assert (select c.slug from messages m join channels c on c.id = m.channel_id
          where m.meta->>'type' = 'new_member' and m.meta->>'member' = '00000000-0000-0000-0000-0000000000a1')
         = 'direttivo', 'nella Sala Direttivo';
end $$;
delete from net.calls;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000ab', 'nuovo@example.com');
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000ab');
select complete_registration('Nuovo', 'Arrivato', 2000, 'NUOVO', null, array['futuro'], false, null, null, 'DC', 5, 'ps5', '{}');
select accept_rules((select max(number) from rules_versions));
do $$ begin
  assert (select count(*) from messages where meta->>'type' = 'new_member') = 0,
    'un giocatore non vede gli avvisi della Sala Direttivo';
end $$;
reset role;
do $$ begin
  assert (select body from messages where meta->>'type' = 'new_member'
          and meta->>'member' = '00000000-0000-0000-0000-0000000000ab')
         = 'Nuovo ingresso: NUOVO (Nuovo Arrivato) · Giocatore · Milan AC Futuro · DC. Se non lo conoscete, toglietelo dalla Rosa.',
    'avviso con nome, ruolo e squadra';
  assert (select count(*) from net.calls where body->>'kind' = 'chat_message') = 1, 'e la notifica al Direttivo';
end $$;

-- Profili di chi non è ancora entrato (nome dell'account o della mail): solo lui e il Direttivo.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
do $$ begin
  assert (select count(*) from profiles where club_role = 'pending') = 0,
    'un giocatore non vede chi è ancora in attesa';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select count(*) from profiles where club_role = 'pending') >= 1, 'il Direttivo sì';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from profiles) = 1, 'chi è in attesa vede solo sé stesso';
end $$;
reset role;
select pg_temp.as_user(null);

-- Un portiere elimina l'account: lo storico delle sue partite non prende il portiere della
-- formazione di oggi, l'eliminazione riesce e non nascono carte.
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000ac', 'portiere@example.com');
update profiles set club_role = 'giocatore', display_name = 'PORTIERE', teams = array['futuro'],
  field_position = 'POR' where id = '00000000-0000-0000-0000-0000000000ac';
update formations set published_at = now() + interval '1 minute',
  published_players = '{"0": "00000000-0000-0000-0000-0000000000e2"}'
  where id = current_setting('test.formazione')::uuid;
insert into matches (id, kind, opponent, played_at, team, goals_for, goals_against, goalkeeper_id) values
  ('00000000-0000-0000-0000-0000000000f7', 'torneo', 'Lince', now() + interval '40 days', 'futuro', 1, 0,
   '00000000-0000-0000-0000-0000000000ac'),
  ('00000000-0000-0000-0000-0000000000f8', 'torneo', 'Tigre', now() + interval '41 days', 'futuro', 1, 0,
   '00000000-0000-0000-0000-0000000000ac');
delete from net.calls;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000ac');
select delete_my_account();
reset role;
select pg_temp.as_user(null);
do $$ begin
  assert not exists (select 1 from profiles where id = '00000000-0000-0000-0000-0000000000ac'), 'account eliminato';
  assert (select count(*) from matches where id in ('00000000-0000-0000-0000-0000000000f7',
          '00000000-0000-0000-0000-0000000000f8') and goalkeeper_id is null) = 2,
    'le sue partite restano senza portiere (non quello della formazione di oggi)';
  assert (select count(*) from net.calls where body->>'kind' = 'special_card') = 0, 'nessuna carta nuova';
end $$;
-- Il portiere della formazione pubblicata non c'è più: i risultati si salvano senza.
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000ae', 'secondo@example.com');
update profiles set club_role = 'giocatore', display_name = 'SECONDO', teams = array['futuro']
  where id = '00000000-0000-0000-0000-0000000000ae';
update formations set published_at = now() + interval '2 minutes',
  published_players = '{"0": "00000000-0000-0000-0000-0000000000ae"}'
  where id = current_setting('test.formazione')::uuid;
delete from auth.users where id = '00000000-0000-0000-0000-0000000000ae';
insert into matches (id, kind, opponent, played_at, team, goals_for, goals_against)
values ('00000000-0000-0000-0000-0000000000f9', 'amichevole', 'Puma', now() + interval '42 days', 'futuro', 2, 2);
do $$ begin
  assert (select goalkeeper_id from matches where id = '00000000-0000-0000-0000-0000000000f9') is null,
    'risultato salvato senza portiere';
end $$;

-- ================================================================ poteri del Direttivo (0026)
-- Partenza: un solo Direttivo attivo (0d).
reset role;
select pg_temp.as_user(null);
update profiles set club_role = 'giocatore'
  where club_role = 'direttivo' and id <> '00000000-0000-0000-0000-00000000000d';
do $$ begin
  assert (select count(*) from profiles where club_role = 'direttivo' and active) = 1, 'un solo Direttivo';
end $$;
delete from messages where meta->>'type' = 'direttivo';

-- Promozione con le etichette: messaggio nella Sala Direttivo con chi l'ha decisa.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
-- Un giocatore non promuove nessuno (la riga degli altri non la può toccare) né sé stesso.
update profiles set club_role = 'direttivo' where id = '00000000-0000-0000-0000-0000000000e2';
select pg_temp.expect_error(
  $q$update profiles set club_role = 'direttivo' where id = '00000000-0000-0000-0000-0000000000e1'$q$,
  'Solo il Direttivo');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select club_role from profiles where id = '00000000-0000-0000-0000-0000000000e2') = 'giocatore',
    'un giocatore non promuove gli altri';
end $$;
update profiles set club_role = 'direttivo', direttivo_roles = array['capitano', 'gestore']
  where id = '00000000-0000-0000-0000-0000000000e1';
reset role;
do $$ begin
  assert (select club_role from profiles where id = '00000000-0000-0000-0000-0000000000e1') = 'direttivo',
    'promosso nel Direttivo';
  assert (select body from messages where meta->>'type' = 'direttivo'
          and meta->>'member' = '00000000-0000-0000-0000-0000000000e1')
         like '% è entrato nel Direttivo (Capitano, Gestore) · nominato da %.', 'avviso della promozione';
end $$;
-- Retrocessione: le etichette si azzerano e resta traccia.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
update profiles set club_role = 'giocatore' where id = '00000000-0000-0000-0000-0000000000e1';
reset role;
do $$ begin
  assert (select direttivo_roles from profiles where id = '00000000-0000-0000-0000-0000000000e1') = '{}',
    'etichette azzerate';
  assert (select count(*) from messages where meta->>'type' = 'direttivo'
          and body like '% non fa più parte del Direttivo · deciso da %') = 1, 'avviso della retrocessione';
end $$;

-- L'ultimo del Direttivo non si può retrocedere, rimuovere né eliminare da solo.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select pg_temp.expect_error(
  $q$update profiles set club_role = 'giocatore' where id = '00000000-0000-0000-0000-00000000000d'$q$,
  'almeno un membro del Direttivo');
select pg_temp.expect_error(
  $q$update profiles set active = false where id = '00000000-0000-0000-0000-00000000000d'$q$,
  'almeno un membro del Direttivo');
select pg_temp.expect_error($q$select delete_my_account()$q$, 'ultimo membro del Direttivo');
-- Con un altro Direttivo sì (tutti hanno gli stessi poteri, anche su sé stessi).
update profiles set club_role = 'direttivo', direttivo_roles = array['organizzatore']
  where id = '00000000-0000-0000-0000-0000000000e2';
update profiles set club_role = 'giocatore' where id = '00000000-0000-0000-0000-00000000000d';
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
update profiles set club_role = 'direttivo', direttivo_roles = array['capitano']
  where id = '00000000-0000-0000-0000-00000000000d';
reset role;
do $$ begin
  assert (select count(*) from profiles where club_role = 'direttivo' and active) = 2, 'due Direttivo';
end $$;

-- Eliminazione dell'account di un altro membro: solo il Direttivo, non il proprio.
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000ad', 'estraneo@example.com');
insert into storage.objects (bucket_id, name) values ('avatars', '00000000-0000-0000-0000-0000000000ad/foto.jpg');
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error(
  $q$select delete_member_account('00000000-0000-0000-0000-0000000000ad')$q$, 'Solo il Direttivo');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select pg_temp.expect_error(
  $q$select delete_member_account('00000000-0000-0000-0000-00000000000d')$q$, 'Impostazioni');
do $$ begin
  assert (select count(*) from profiles where id = '00000000-0000-0000-0000-0000000000ad'
          and club_role = 'pending') = 1, 'il Direttivo vede chi è registrato ma non è entrato';
end $$;
select delete_member_account('00000000-0000-0000-0000-0000000000ad');
reset role;
do $$ begin
  assert not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000ad'), 'account eliminato';
  assert not exists (select 1 from profiles where id = '00000000-0000-0000-0000-0000000000ad'), 'profilo eliminato';
  assert (select count(*) from storage_cleanup
          where path = '00000000-0000-0000-0000-0000000000ad/foto.jpg') = 1, 'foto in coda per lo Storage';
  assert (select count(*) from messages where meta->>'type' = 'account_deleted'
          and body like 'Account di estraneo eliminato da %.') = 1, 'traccia nella Sala Direttivo';
end $$;

-- Foto del profilo: il Direttivo può toglierla, un giocatore no.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a9');
delete from storage.objects where bucket_id = 'avatars' and name = '00000000-0000-0000-0000-0000000000e1/foto.jpg';
reset role;
do $$ begin
  assert (select count(*) from storage.objects where bucket_id = 'avatars'
          and name = '00000000-0000-0000-0000-0000000000e1/foto.jpg') = 1, 'un giocatore non toglie la foto altrui';
end $$;
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
delete from storage.objects where bucket_id = 'avatars' and name = '00000000-0000-0000-0000-0000000000e1/foto.jpg';
update profiles set avatar_path = null where id = '00000000-0000-0000-0000-0000000000e1';
reset role;
do $$ begin
  assert (select count(*) from storage.objects where bucket_id = 'avatars'
          and name = '00000000-0000-0000-0000-0000000000e1/foto.jpg') = 0, 'il Direttivo toglie la foto';
  assert (select avatar_path from profiles where id = '00000000-0000-0000-0000-0000000000e1') is null,
    'e il riferimento nel profilo';
end $$;

-- Stanza vocale chiusa dal Direttivo per tutti.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select set_config('test.stanza_c', open_voice_room((select id from channels where slug = 'main'))::text, false);
select set_config('test.sessione_c', (select id from voice_sessions
  where room_id = current_setting('test.stanza_c')::uuid and left_at is null)::text, false);
select pg_temp.expect_error(
  $q$select close_voice_room(current_setting('test.stanza_c')::uuid)$q$, 'Solo il Direttivo');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select close_voice_room(current_setting('test.stanza_c')::uuid);
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
do $$ begin
  assert voice_heartbeat(current_setting('test.sessione_c')::uuid) = false,
    'il telefono di chi era dentro scopre che la stanza è chiusa';
end $$;
reset role;
do $$ begin
  assert (select closed_at is not null from voice_rooms where id = current_setting('test.stanza_c')::uuid),
    'stanza chiusa';
  assert (select count(*) from voice_sessions where room_id = current_setting('test.stanza_c')::uuid
          and left_at is null) = 0, 'nessuno resta dentro';
end $$;

-- ================================================================ diretta TV (0027)
-- I minuti dei gol: facoltativi, validi e mai più dei gol del risultato.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into matches (id, kind, opponent, played_at, team, goals_for, goals_against, scorers, timeline)
values ('00000000-0000-0000-0000-0000000000bd', 'amichevole', 'Diretta', now(), 'milanac', 2, 1, 'Rossi (2)',
        '[{"minute": 18, "side": "them"}, {"minute": 52, "side": "us", "scorer": "Rossi"}]');
select pg_temp.expect_error(format(
  $q$update matches set timeline = %L where id = '00000000-0000-0000-0000-0000000000bd'$q$, t),
  'matches_timeline_valid')
from unnest(array[
  '{}',                                                -- non è un elenco
  '[{"minute": 0, "side": "us"}]',                     -- minuto fuori misura
  '[{"minute": 131, "side": "us"}]',
  '[{"minute": 12.5, "side": "us"}]',                  -- minuto non intero
  '[{"minute": "12", "side": "us"}]',                  -- minuto scritto come testo
  '[{"minute": 12}]',                                  -- di chi è il gol?
  '[{"minute": 12, "side": "noi"}]',
  '[{"minute": 12, "side": "us", "scorer": 5}]',
  '[{"minute": 12, "side": "us", "scorer": "' || repeat('x', 61) || '"}]',
  '[{"minute": 1, "side": "us"}, {"minute": 2, "side": "us"}, {"minute": 3, "side": "us"}]',
  '[{"minute": 5, "side": "them"}, {"minute": 6, "side": "them"}]'
]) t;
-- Il risultato non scende sotto i gol con il minuto.
select pg_temp.expect_error(
  $q$update matches set goals_for = 0 where id = '00000000-0000-0000-0000-0000000000bd'$q$,
  'matches_timeline_valid');
update matches set timeline = '[{"minute": 18, "side": "them"}, {"minute": 52, "side": "us", "scorer": "Rossi"},
                                {"minute": 90, "side": "us", "scorer": null}]'
  where id = '00000000-0000-0000-0000-0000000000bd';
-- Un giocatore non li cambia.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
update matches set timeline = '[]' where id = '00000000-0000-0000-0000-0000000000bd';
reset role;
do $$ begin
  assert (select jsonb_array_length(timeline) from matches
          where id = '00000000-0000-0000-0000-0000000000bd') = 3, 'minuti salvati dal Direttivo';
  assert not exists (select 1 from matches
                     where id <> '00000000-0000-0000-0000-0000000000bd' and timeline <> '[]'::jsonb),
    'le partite di prima restano senza minuti';
end $$;

-- ================================================================ archetipi e PlayStyle (0028)
-- Il giocatore sceglie i suoi PlayStyle (al massimo 6, di cui 2 "+", senza doppioni).
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
update profiles set play_style = 'Finalizzatore',
                    play_styles = '{tiro_potente+,scatto,primo_controllo}'
  where id = '00000000-0000-0000-0000-0000000000e1';
select pg_temp.expect_error(format(
  $q$update profiles set play_styles = %L where id = '00000000-0000-0000-0000-0000000000e1'$q$, s),
  'profiles_play_styles_valid')
from unnest(array[
  '{a1,b2,c3,d4,e5,f6,g7}',                       -- più di 6 (e codici non validi)
  '{uno,due,tre,quattro,cinque,sei,sette}',       -- più di 6
  '{tiro_potente+,scatto+,rapido+}',              -- più di 2 "+"
  '{scatto,scatto+}',                             -- doppione
  '{Tiro}',                                       -- maiuscole
  '{tiro potente}',                               -- spazio
  '{x}'                                           -- troppo corto
]) s;
-- Gli altri non cambiano i PlayStyle di un compagno (la riga non è sua).
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a9');
update profiles set play_styles = '{}' where id = '00000000-0000-0000-0000-0000000000e1';
reset role;
do $$ begin
  assert (select play_styles from profiles where id = '00000000-0000-0000-0000-0000000000e1')
         = '{tiro_potente+,scatto,primo_controllo}', 'PlayStyle salvati dal giocatore';
  assert (select count(*) from profiles where play_styles is null) = 0, 'mai null';
end $$;

-- ================================================================ Match Day (0029)
-- Il codice del party lo scrive il Direttivo; un giocatore no.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
insert into events (id, type, title, starts_at)
values ('00000000-0000-0000-0000-0000000000c9', 'torneo', 'FVPA – 4ª giornata vs Lupi', now() + interval '3 hours');
update events set party_code = 'MILANAC21' where id = '00000000-0000-0000-0000-0000000000c9';
select pg_temp.expect_error(
  $q$update events set party_code = '   ' where id = '00000000-0000-0000-0000-0000000000c9'$q$,
  'events_party_code_len');
select pg_temp.expect_error(format(
  $q$update events set party_code = %L where id = '00000000-0000-0000-0000-0000000000c9'$q$,
  repeat('x', 41)), 'events_party_code_len');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
update events set party_code = 'INTRUSO' where id = '00000000-0000-0000-0000-0000000000c9';
reset role;
do $$ begin
  assert (select party_code from events where id = '00000000-0000-0000-0000-0000000000c9') = 'MILANAC21',
    'il codice resta quello del Direttivo';
end $$;

-- ================================================================ sondaggi in chat (0030)
-- Tre giocatori: 5a1 e 5a2 nella squadra Milan AC, 5a3 solo nel Futuro.
reset role;
select pg_temp.as_user(null);
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000005a1', 'sondaggi1@example.com'),
  ('00000000-0000-0000-0000-0000000005a2', 'sondaggi2@example.com'),
  ('00000000-0000-0000-0000-0000000005a3', 'sondaggi3@example.com');
update profiles set club_role = 'giocatore', active = true, teams = array['milanac']
  where id in ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000005a2');
update profiles set club_role = 'giocatore', active = true, teams = array['futuro']
  where id = '00000000-0000-0000-0000-0000000005a3';
do $$ begin
  assert valid_poll_meta('{"type": "poll", "options": ["Martedì", "Mercoledì"]}'), 'due opzioni';
  assert valid_poll_meta('{"type": "poll", "options": ["A", "B", "C"], "multiple": true}'), 'scelta multipla';
  assert not valid_poll_meta('{"type": "poll", "options": ["Solo una"]}'), 'una opzione non basta';
  assert not valid_poll_meta('{"type": "poll", "options": ["A", "a "]}'), 'opzioni uguali';
  assert not valid_poll_meta('{"type": "poll", "options": ["A", "  "]}'), 'opzione vuota';
  assert not valid_poll_meta('{"type": "poll", "options": ["A", 2]}'), 'opzione non testo';
  assert not valid_poll_meta('{"type": "poll", "options": "A,B"}'), 'opzioni non in elenco';
  assert not valid_poll_meta('{"type": "poll", "options": ["A", "B"], "multiple": "sì"}'), 'multiple non booleano';
  assert not valid_poll_meta(jsonb_build_object('type', 'poll', 'options',
    (select jsonb_agg(i::text) from generate_series(1, 11) i))), 'più di 10 opzioni';
  assert not valid_poll_meta(jsonb_build_object('type', 'poll', 'options',
    jsonb_build_array('A', repeat('x', 81)))), 'opzione oltre 80 caratteri';
end $$;

-- Il giocatore crea un sondaggio nel canale della sua squadra (anche "chiuso" nasce aperto).
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000005a1');
insert into messages (id, channel_id, body, meta)
select '00000000-0000-0000-0000-0000000005b1', id, 'Quando giochiamo l''amichevole?',
       '{"type": "poll", "options": ["Martedì", "Mercoledì", "Giovedì"], "closed_at": "2026-01-01T00:00:00Z"}'
from channels where slug = 'milanac';
insert into messages (id, channel_id, body, meta)
select '00000000-0000-0000-0000-0000000005b2', id, 'Che cosa portiamo al torneo?',
       '{"type": "poll", "options": ["Maglie nuove", "Cuffie", "Pizza"], "multiple": true}'
from channels where slug = 'milanac';
select pg_temp.expect_error(
  $q$insert into messages (channel_id, body, meta) select id, 'Una sola?', '{"type": "poll", "options": ["Sì"]}' from channels where slug = 'milanac'$q$,
  'messages_poll_valid');
select pg_temp.expect_error(
  $q$insert into messages (channel_id, body, meta) select id, '  ', '{"type": "poll", "options": ["Sì", "No"]}' from channels where slug = 'milanac'$q$,
  'violates check constraint');
select pg_temp.expect_error(format(
  $q$insert into messages (channel_id, body, meta) select id, %L, '{"type": "poll", "options": ["Sì", "No"]}' from channels where slug = 'milanac'$q$,
  repeat('x', 301)), 'messages_poll_valid');
select pg_temp.expect_error(
  $q$insert into messages (channel_id, body, image_path, meta) select id, 'Con foto?', '00000000-0000-0000-0000-0000000005a1/x.jpg', '{"type": "poll", "options": ["Sì", "No"]}' from channels where slug = 'milanac'$q$,
  'messages_poll_valid');
do $$ begin
  assert not (select meta ? 'closed_at' from messages where id = '00000000-0000-0000-0000-0000000005b1'),
    'il sondaggio nasce aperto';
end $$;

-- Si vota (una opzione), si cambia idea, si ritira il voto; niente opzioni fuori elenco
-- o doppie dove se ne sceglie una sola.
select vote_poll('00000000-0000-0000-0000-0000000005b1', array[0]);
select vote_poll('00000000-0000-0000-0000-0000000005b1', array[1]);
select pg_temp.expect_error(
  $q$select vote_poll('00000000-0000-0000-0000-0000000005b1', array[0, 2])$q$, 'una sola opzione');
select pg_temp.expect_error(
  $q$select vote_poll('00000000-0000-0000-0000-0000000005b1', array[3])$q$, 'Opzione non valida');
select pg_temp.expect_error(
  $q$select vote_poll('00000000-0000-0000-0000-0000000005b1', array[-1])$q$, 'Opzione non valida');
select pg_temp.expect_error(
  $q$select vote_poll('00000000-0000-0000-0000-0000000005b1', array[null]::int[])$q$, 'Opzione non valida');
select vote_poll('00000000-0000-0000-0000-0000000005b2', array[2, 0, 2]);
select pg_temp.as_user('00000000-0000-0000-0000-0000000005a2');
select vote_poll('00000000-0000-0000-0000-0000000005b1', array[1]);
select vote_poll('00000000-0000-0000-0000-0000000005b2', array[0]);
select vote_poll('00000000-0000-0000-0000-0000000005b2', '{}');
-- Niente scritture dirette sui voti, nemmeno a nome proprio.
select pg_temp.expect_error(
  $q$insert into poll_votes (message_id, user_id, options) values ('00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000005a2', '{2}')$q$,
  'row-level security');
do $$ begin
  assert (select options from poll_votes where message_id = '00000000-0000-0000-0000-0000000005b1'
          and user_id = '00000000-0000-0000-0000-0000000005a1') = '{1}', 'voto cambiato';
  assert (select count(*) from poll_votes where message_id = '00000000-0000-0000-0000-0000000005b1'
          and 1 = any(options)) = 2, 'due voti per mercoledì';
  assert (select options from poll_votes where message_id = '00000000-0000-0000-0000-0000000005b2'
          and user_id = '00000000-0000-0000-0000-0000000005a1') = '{0,2}', 'scelte multiple senza doppioni';
  assert (select options from poll_votes where message_id = '00000000-0000-0000-0000-0000000005b2'
          and user_id = '00000000-0000-0000-0000-0000000005a2') = '{}', 'voto ritirato';
end $$;

-- Chi è solo nel Futuro non vede né vota il sondaggio della prima squadra.
select pg_temp.as_user('00000000-0000-0000-0000-0000000005a3');
select pg_temp.expect_error(
  $q$select vote_poll('00000000-0000-0000-0000-0000000005b1', array[0])$q$, 'Sondaggio non trovato');
select pg_temp.expect_error(
  $q$select close_poll('00000000-0000-0000-0000-0000000005b1')$q$, 'Sondaggio non trovato');
do $$ begin
  assert (select count(*) from poll_votes) = 0, 'i voti di un canale non visibile restano nascosti';
end $$;
-- Un messaggio normale non è un sondaggio.
select pg_temp.as_user('00000000-0000-0000-0000-0000000005a1');
insert into messages (id, channel_id, body)
select '00000000-0000-0000-0000-0000000005b3', id, 'Messaggio normale' from channels where slug = 'milanac';
select pg_temp.expect_error(
  $q$select vote_poll('00000000-0000-0000-0000-0000000005b3', array[0])$q$, 'Sondaggio non trovato');

-- Lo chiude chi l'ha creato (o il Direttivo), non un altro giocatore; chiuso, non si vota più.
select pg_temp.as_user('00000000-0000-0000-0000-0000000005a2');
select pg_temp.expect_error(
  $q$select close_poll('00000000-0000-0000-0000-0000000005b1')$q$, 'solo chi l''ha creato');
select pg_temp.as_user('00000000-0000-0000-0000-0000000005a1');
do $$ begin
  assert close_poll('00000000-0000-0000-0000-0000000005b1') ? 'closed_at', 'chiuso dall''autore';
end $$;
select pg_temp.expect_error(
  $q$select vote_poll('00000000-0000-0000-0000-0000000005b1', array[0])$q$, 'chiuso');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert close_poll('00000000-0000-0000-0000-0000000005b2') ? 'closed_at', 'chiuso dal Direttivo';
  assert (select count(*) from poll_votes where message_id = '00000000-0000-0000-0000-0000000005b1') = 2,
    'il Direttivo vede i voti';
end $$;
-- Eliminato il sondaggio, spariscono anche i voti.
delete from messages where id = '00000000-0000-0000-0000-0000000005b1';
reset role;
do $$ begin
  assert (select count(*) from poll_votes where message_id = '00000000-0000-0000-0000-0000000005b1') = 0,
    'voti eliminati con il sondaggio';
end $$;

-- ================================================================ promemoria partita (0031)
-- Partite di lunedì 2 novembre 2026 alle 21:30 (ora italiana): m1 in calendario da giorni,
-- m2 creata alle 21:00 (ha già avuto la sua notifica), un allenamento che non conta.
reset role;
select pg_temp.as_user(null);
delete from net.calls;
insert into events (id, type, title, starts_at, team, created_at) values
  ('00000000-0000-0000-0000-0000000006e1', 'torneo', 'FVPA – 5ª giornata vs Lupi',
   '2026-11-02 21:30 Europe/Rome', 'milanac', '2026-10-28 12:00 Europe/Rome'),
  ('00000000-0000-0000-0000-0000000006e2', 'amichevole', 'Amichevole vs Orsi',
   '2026-11-02 21:30 Europe/Rome', 'futuro', '2026-11-02 21:00 Europe/Rome'),
  ('00000000-0000-0000-0000-0000000006e3', 'allenamento', 'Allenamento',
   '2026-11-02 21:30 Europe/Rome', null, '2026-10-28 12:00 Europe/Rome');
delete from net.calls;
create function pg_temp.reminders(p_when text) returns int language sql as $$
  select count(*)::int from net.calls
  where body->>'kind' = 'match_reminder' and body->>'when' = p_when
$$;
select set_config('milanac.now', '2026-11-02 20:20 Europe/Rome', false);
select match_reminders_tick();
do $$ begin
  assert pg_temp.reminders('ora') + pg_temp.reminders('lobby') = 0, 'più di un''ora prima: niente';
end $$;
select set_config('milanac.now', '2026-11-02 20:31 Europe/Rome', false);
select match_reminders_tick();
select match_reminders_tick();
do $$ begin
  assert pg_temp.reminders('ora') = 1, 'un''ora prima, una volta sola e solo per m1';
  assert (select body->>'id' from net.calls where body->>'when' = 'ora')
         = '00000000-0000-0000-0000-0000000006e1', 'l''avviso dell''ora è di m1';
  assert pg_temp.reminders('lobby') = 0, 'la lobby non ancora';
end $$;
-- m3: in calendario da giorni ma il controllo di pg_cron non è girato fino a 9 minuti
-- prima: niente "tra un'ora" in ritardo, solo la lobby.
insert into events (id, type, title, starts_at, team, created_at) values
  ('00000000-0000-0000-0000-0000000006e4', 'torneo', 'Coppa vs Falchi',
   '2026-11-02 21:30 Europe/Rome', 'milanac', '2026-10-20 12:00 Europe/Rome');
select set_config('milanac.now', '2026-11-02 21:21 Europe/Rome', false);
select match_reminders_tick();
select match_reminders_tick();
do $$ begin
  assert pg_temp.reminders('ora') = 1, 'niente "tra un''ora" a 9 minuti dall''inizio';
  assert pg_temp.reminders('lobby') = 3, 'lobby per le tre partite, una volta sola';
  assert not exists (select 1 from net.calls where body->>'id' = '00000000-0000-0000-0000-0000000006e3'
                     and body->>'kind' = 'match_reminder'), 'l''allenamento non ha promemoria';
end $$;
select set_config('milanac.now', '2026-11-02 21:45 Europe/Rome', false);
select match_reminders_tick();
do $$ begin
  assert pg_temp.reminders('ora') + pg_temp.reminders('lobby') = 4, 'a partita iniziata niente di nuovo';
end $$;
-- La partita m3 si sposta a martedì: i promemoria ripartono per il nuovo orario.
update events set starts_at = '2026-11-03 21:30 Europe/Rome'
  where id = '00000000-0000-0000-0000-0000000006e4';
select set_config('milanac.now', '2026-11-03 20:31 Europe/Rome', false);
select match_reminders_tick();
select set_config('milanac.now', '2026-11-03 21:21 Europe/Rome', false);
select match_reminders_tick();
select match_reminders_tick();
do $$ begin
  assert pg_temp.reminders('ora') = 2 and pg_temp.reminders('lobby') = 4,
    'partita spostata: di nuovo "tra un''ora" e lobby, una volta sola';
end $$;

-- La chiamata in lobby: solo il Direttivo, solo per le partite e nelle ore della partita,
-- al massimo una ogni 3 minuti.
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.expect_error(
  $q$select call_to_lobby('00000000-0000-0000-0000-0000000006e1')$q$, 'Solo il Direttivo');
do $$ begin
  assert (select count(*) from event_reminders) = 0, 'i promemoria non si leggono dall''app';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select set_config('milanac.now', '2026-11-02 21:25 Europe/Rome', false);
do $$ begin
  assert call_to_lobby('00000000-0000-0000-0000-0000000006e1') = '2026-11-02 21:25 Europe/Rome'::timestamptz,
    'chiamata alle 21:25';
end $$;
select pg_temp.expect_error(
  $q$select call_to_lobby('00000000-0000-0000-0000-0000000006e1')$q$, 'chiamata da poco');
select pg_temp.expect_error(
  $q$select call_to_lobby('00000000-0000-0000-0000-0000000006e3')$q$, 'Partita non trovata');
select set_config('milanac.now', '2026-11-02 21:29 Europe/Rome', false);
select call_to_lobby('00000000-0000-0000-0000-0000000006e1');
select set_config('milanac.now', '2026-11-02 18:00 Europe/Rome', false);
select pg_temp.expect_error(
  $q$select call_to_lobby('00000000-0000-0000-0000-0000000006e2')$q$, 'nelle ore della partita');
reset role;
do $$ begin
  assert pg_temp.reminders('chiamata') = 2, 'due chiamate a quattro minuti di distanza';
  assert (select count(*) from event_reminders where kind = 'chiamata'
          and sent_by = '00000000-0000-0000-0000-00000000000d') = 2, 'si sa chi ha chiamato';
end $$;
-- Eliminata la partita, spariscono anche i suoi promemoria.
delete from events where id = '00000000-0000-0000-0000-0000000006e1';
do $$ begin
  assert (select count(*) from event_reminders
          where event_id = '00000000-0000-0000-0000-0000000006e1') = 0, 'promemoria eliminati';
end $$;
select set_config('milanac.now', '', false);
