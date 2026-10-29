-- Partita come in una diretta TV (ottobre 2026): i minuti dei gol per il tabellone, la
-- timeline e la cronaca. Facoltativi: le partite di prima restano senza.
--   timeline = [{"minute": 52, "side": "us", "scorer": "Rossi"}, {"minute": 18, "side": "them"}]
-- "scorer" solo per i gol del club, scritto come nei marcatori (il nome si riconosce come lì).
-- I gol con il minuto non possono essere più di quelli del risultato.

create or replace function public.valid_match_timeline(t jsonb, gf integer, ga integer)
returns boolean language sql immutable set search_path = public as $$
  select jsonb_typeof(t) = 'array'
     and jsonb_array_length(t) <= 40
     and not exists (
       select 1 from jsonb_array_elements(t) e
       where case
               when jsonb_typeof(e) <> 'object' then true
               when coalesce(jsonb_typeof(e->'minute'), '') <> 'number' then true
               when (e->>'minute')::numeric not between 1 and 130 then true
               when (e->>'minute')::numeric <> trunc((e->>'minute')::numeric) then true
               when coalesce(e->>'side', '') not in ('us', 'them') then true
               when coalesce(jsonb_typeof(e->'scorer'), 'null') not in ('string', 'null') then true
               when length(coalesce(e->>'scorer', '')) > 60 then true
               else false
             end)
     and (select count(*) from jsonb_array_elements(t) e where e->>'side' = 'us')
         <= coalesce(gf, 0)
     and (select count(*) from jsonb_array_elements(t) e where e->>'side' = 'them')
         <= coalesce(ga, 0)
$$;

alter table public.matches add column if not exists timeline jsonb not null default '[]'::jsonb;
alter table public.matches drop constraint if exists matches_timeline_valid;
alter table public.matches add constraint matches_timeline_valid
  check (public.valid_match_timeline(timeline, goals_for, goals_against));
