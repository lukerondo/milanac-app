-- Fase 4 (ottobre 2026): lavagna tattica con replay.
-- Gli schemi disegnati sulla lavagna (gettoni, heatmap, frecce) si salvano in tactics con
-- l'immagine esportata; il replay (voce più movimenti con i tempi, fino a 5 minuti) va in chat
-- come messaggio con due file (audio e azioni) e scade dopo 3 giorni.

-- ---------------------------------------------------------------- 1) schemi della lavagna
alter table public.tactics
  add column if not exists board jsonb,   -- gettoni, heatmap, frecce, modulo di partenza
  add column if not exists team text;     -- squadra della rosa usata (milanac|futuro)
alter table public.tactics drop constraint if exists tactics_team_check;
alter table public.tactics add constraint tactics_team_check
  check (team is null or team in ('milanac', 'futuro'));
alter table public.tactics drop constraint if exists tactics_board_check;
alter table public.tactics add constraint tactics_board_check
  check (board is null or (jsonb_typeof(board) = 'object' and pg_column_size(board) <= 300000));

-- ---------------------------------------------------------------- 2) replay in chat
alter table public.messages add column if not exists replay_path text;  -- azioni con i tempi (JSON)

-- Un vocale normale dura al massimo 2 minuti; il replay della lavagna fino a 5.
alter table public.messages drop constraint if exists messages_duration_s_check;
alter table public.messages add constraint messages_duration_s_check
  check (duration_s is null or duration_s between 1 and 300);
alter table public.messages drop constraint if exists messages_voice_duration_check;
alter table public.messages add constraint messages_voice_duration_check
  check (expired_at is not null or replay_path is not null or duration_s is null or duration_s <= 120);
alter table public.messages drop constraint if exists messages_check;
alter table public.messages add constraint messages_check
  check (coalesce(btrim(body), '') <> '' or image_path is not null or audio_path is not null
         or replay_path is not null or expired_at is not null);

-- Il file delle azioni (JSON) sta nel bucket della chat, accanto all'audio.
update storage.buckets
set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp',
                               'audio/mp4', 'audio/aac', 'audio/x-m4a', 'audio/m4a',
                               'audio/mpeg', 'audio/ogg', 'audio/webm', 'audio/wav',
                               'application/json']
where id = 'chat';

-- Il replay scade dopo 3 giorni, foto e vocali dopo 60.
create or replace function public.messages_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.reply_to is not null and not exists (
       select 1 from messages r where r.id = new.reply_to and r.channel_id = new.channel_id) then
    raise exception 'Si può rispondere solo a un messaggio dello stesso canale';
  end if;
  new.expired_at := null;
  new.expires_at := case
    when new.replay_path is not null then app_now() + interval '3 days'
    when new.image_path is not null or new.audio_path is not null then app_now() + interval '60 days'
  end;
  return new;
end $$;

create or replace function public.messages_after_delete() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into storage_cleanup (bucket, path)
  select 'chat', p
  from (values (old.image_path), (old.audio_path), (old.replay_path)) v(p)
  where p is not null
  on conflict do nothing;
  return old;
end $$;

create or replace function public.expire_attachments() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into storage_cleanup (bucket, path)
  select 'chat', p
  from messages m
  cross join lateral (values (m.image_path), (m.audio_path), (m.replay_path)) v(p)
  where m.expires_at <= app_now() and m.expired_at is null and p is not null
  on conflict do nothing;
  update messages
  set expired_at = app_now(), image_path = null, audio_path = null, replay_path = null
  where expires_at <= app_now() and expired_at is null;
  get diagnostics n = row_count;
  if exists (select 1 from storage_cleanup) then
    perform notify_push(jsonb_build_object('kind', 'cleanup'));
  end if;
  return n;
end $$;

-- Riepilogo dei canali: anche il tipo dell'ultimo messaggio (replay, annuncio...).
drop function if exists public.chat_overview();
create or replace function public.chat_overview()
returns table (channel_id uuid, unread int, last_body text, last_author text, last_kind text,
               last_has_image boolean, last_has_audio boolean, last_type text, last_at timestamptz)
language sql stable set search_path = public as $$
  select c.id,
         (select count(*) from (
            select 1 from messages m
            where m.channel_id = c.id
              and m.created_at > coalesce(r.last_read_at, '-infinity'::timestamptz)
              and m.author_id is distinct from auth.uid()
            limit 99) u)::int,
         lm.body, lm.author, lm.kind, lm.image_path is not null, lm.audio_path is not null,
         lm.meta->>'type', lm.created_at
  from channels c
  left join channel_reads r on r.channel_id = c.id and r.user_id = auth.uid()
  left join lateral (
    select m.body, m.kind, m.image_path, m.audio_path, m.meta, m.created_at, p.display_name as author
    from messages m left join profiles p on p.id = m.author_id
    where m.channel_id = c.id
    order by m.created_at desc
    limit 1
  ) lm on true
  order by c.sort_order
$$;
revoke all on function public.chat_overview() from public, anon;
grant execute on function public.chat_overview() to authenticated;
