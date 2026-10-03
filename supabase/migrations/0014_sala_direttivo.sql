-- Sala Direttivo: canale chat riservato, avvisi ufficiali e formazione pubblicata "congelata".

-- 1) Canali riservati al Direttivo: invisibili (lista, messaggi, notifiche) agli altri membri.
alter table public.channels add column if not exists direttivo_only boolean not null default false;

insert into public.channels (slug, name, description, icon, sort_order, direttivo_only)
values ('direttivo', 'Sala Direttivo', 'Solo per il Direttivo: decisioni, mercato, formazioni', 'direttivo', 10, true)
on conflict (slug) do nothing;

drop policy if exists "lettura membri" on public.channels;
create policy "lettura membri" on public.channels for select
  using (is_member() and (not direttivo_only or is_direttivo()));

-- I messaggi seguono la visibilità del canale (la sottoquery rispetta la policy sui canali).
drop policy if exists "lettura membri" on public.messages;
create policy "lettura membri" on public.messages for select
  using (is_member() and exists (select 1 from channels c where c.id = channel_id));

-- Scrivere solo nei canali visibili; gli "avvisi" ufficiali li manda solo il Direttivo.
drop policy if exists "membri scrivono" on public.messages;
create policy "membri scrivono" on public.messages for insert
  with check (
    is_member() and author_id = auth.uid() and kind = 'user'
    and exists (select 1 from channels c where c.id = channel_id)
    and (meta is null or meta->>'type' is distinct from 'announcement' or is_direttivo())
  );

-- 2) Formazione pubblicata: modulo e giocatori "congelati" al momento della pubblicazione.
--    I giocatori vedono questa versione; il Direttivo può preparare la prossima in bozza.
alter table public.formations
  add column if not exists published_module text,
  add column if not exists published_players jsonb;

update public.formations f
set published_module = f.module,
    published_players = coalesce((
      select jsonb_object_agg(s.slot_index::text, s.player_id)
      from public.formation_slots s
      where s.formation_id = f.id and s.player_id is not null), '{}'::jsonb)
where f.published_at is not null and f.published_players is null;
