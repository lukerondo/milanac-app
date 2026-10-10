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
update profiles set birth_date = '1998-05-12', city = 'Milano', nationality = 'IT',
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
select pg_temp.expect_error(
  $q$select complete_registration('Fabio', 'Bianchi', 1990, 'BIANCHI', null, array['milanac', 'futuro'], true, 'sbagliata', array['capitano'], 'CC', 10, 'ps5', '{}')$q$,
  'Password del Direttivo');
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
