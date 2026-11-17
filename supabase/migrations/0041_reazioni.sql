-- Reazioni ai messaggi della chat (novembre 2026). Chi vede il canale mette un'emoji su un
-- messaggio; una a testa, cambiarla la sostituisce, rimetterla uguale non serve: per toglierla
-- si passa null. Stanno nel meta del messaggio:
--   meta.reactions = {"<id di chi reagisce>": "👍", ...}
-- così arrivano con il messaggio (anche in tempo reale, come la chiusura di un sondaggio) senza
-- altre tabelle né altri abbonamenti. Le scrive solo react_message: i messaggi non si
-- modificano dall'app e un messaggio nuovo nasce senza reazioni.

-- Un'emoji, anche composta (bandiere, toni della pelle, famiglie): al massimo 12 caratteri,
-- tutti tra i simboli delle emoji, e almeno uno che non sia un semplice modificatore.
create or replace function public.valid_reaction(p text) returns boolean
language sql immutable set search_path = public as $$
  select p is not null
     and char_length(p) between 1 and 12
     and p ~ '^[\U0001F000-\U0001FAFF←-⯿‼⁉™ℹ〰〽㊗㊙©®️‍⃣\U000E0020-\U000E007F]+$'
     and p ~ '[\U0001F000-\U0001F3FA\U0001F400-\U0001FAFF←-⯿‼⁉™ℹ〰〽㊗㊙©®]'
$$;
revoke all on function public.valid_reaction(text) from public, anon;
grant execute on function public.valid_reaction(text) to authenticated;

-- Un messaggio nuovo non porta reazioni già scritte da chi lo manda.
create or replace function public.messages_reactions_before_insert() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.meta ? 'reactions' then new.meta := new.meta - 'reactions'; end if;
  return new;
end $$;
drop trigger if exists messages_reactions_before_insert on public.messages;
create trigger messages_reactions_before_insert before insert on public.messages
  for each row execute function public.messages_reactions_before_insert();

-- Mette [p_emoji] come reazione di chi chiama al messaggio (al posto di quella di prima);
-- null o vuoto la toglie. Vale nei canali che si vedono, anche dove scrive solo il Direttivo
-- (Comunicazioni): reagire non è scrivere. Restituisce il meta aggiornato.
create or replace function public.react_message(p_message uuid, p_emoji text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  m record;
  emoji text := nullif(btrim(coalesce(p_emoji, '')), '');
  reactions jsonb;
  saved jsonb;
begin
  -- Il messaggio resta fermo finché la reazione è scritta: due persone che reagiscono
  -- nello stesso momento non si cancellano a vicenda.
  select id, channel_id, kind, meta into m from messages where id = p_message for update;
  if not found or uid is null or not can_see_channel(m.channel_id) then
    raise exception 'Messaggio non trovato';
  end if;
  if m.kind <> 'user' then
    raise exception 'A questo messaggio non si può reagire';
  end if;
  if emoji is not null and not valid_reaction(emoji) then
    raise exception 'Reazione non valida';
  end if;
  reactions := case when jsonb_typeof(m.meta->'reactions') = 'object'
                    then m.meta->'reactions' else '{}'::jsonb end;
  reactions := reactions - uid::text;
  if emoji is not null then
    reactions := reactions || jsonb_build_object(uid::text, emoji);
  end if;
  update messages
  set meta = (coalesce(meta, '{}'::jsonb) - 'reactions')
             || case when reactions = '{}'::jsonb then '{}'::jsonb
                     else jsonb_build_object('reactions', reactions) end
  where id = p_message
  returning meta into saved;
  return saved;
end $$;
revoke all on function public.react_message(uuid, text) from public, anon;
grant execute on function public.react_message(uuid, text) to authenticated;
