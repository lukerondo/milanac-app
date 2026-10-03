-- Link condivisi dal club: playlist della colonna sonora, video delle build dei creator.
-- Tutti i membri li vedono e possono aggiungerne; ognuno modifica i propri, il Direttivo tutti.

create table if not exists public.shared_links (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('musica', 'build')),
  title text not null check (char_length(title) between 1 and 120),
  url text not null check (url ~* '^https?://'),
  note text check (note is null or char_length(note) <= 300),
  tag text check (tag is null or char_length(tag) <= 20),   -- es. ruolo della build (ATT, DC…)
  sort_order int not null default 0,
  created_by uuid default auth.uid() references public.profiles on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists shared_links_category_idx on public.shared_links (category, sort_order);

alter table public.shared_links enable row level security;
drop policy if exists "lettura membri" on public.shared_links;
create policy "lettura membri" on public.shared_links for select using (is_member());
drop policy if exists "membri aggiungono" on public.shared_links;
create policy "membri aggiungono" on public.shared_links for insert
  with check (is_member() and created_by = auth.uid());
drop policy if exists "autore o direttivo modificano" on public.shared_links;
create policy "autore o direttivo modificano" on public.shared_links for update
  using (is_direttivo() or (is_member() and created_by = auth.uid()))
  with check (is_direttivo() or (is_member() and created_by = auth.uid()));
drop policy if exists "autore o direttivo eliminano" on public.shared_links;
create policy "autore o direttivo eliminano" on public.shared_links for delete
  using (is_direttivo() or (is_member() and created_by = auth.uid()));

-- Primi link della colonna sonora: ricerche su YouTube e Spotify (nessun file copiato).
insert into public.shared_links (category, title, url, note, sort_order, created_by)
select * from (values
  ('musica', 'Le canzoni più iconiche di FIFA', 'https://www.youtube.com/results?search_query=canzoni+iconiche+FIFA+soundtrack', 'Compilation su YouTube', 0, null::uuid),
  ('musica', 'FIFA anni 2000', 'https://www.youtube.com/results?search_query=FIFA+2000s+soundtrack', 'Da FIFA 98 a FIFA 09', 1, null::uuid),
  ('musica', 'FIFA anni 2010', 'https://www.youtube.com/results?search_query=FIFA+2010s+soundtrack', 'Da FIFA 10 a FIFA 19', 2, null::uuid),
  ('musica', 'EA SPORTS FC', 'https://www.youtube.com/results?search_query=EA+SPORTS+FC+soundtrack', 'Le colonne sonore più recenti', 3, null::uuid),
  ('musica', 'Playlist FIFA su Spotify', 'https://open.spotify.com/search/FIFA%20soundtrack', 'Si apre nell''app di Spotify', 4, null::uuid)
) as seed(category, title, url, note, sort_order, created_by)
where not exists (select 1 from public.shared_links where category = 'musica');
