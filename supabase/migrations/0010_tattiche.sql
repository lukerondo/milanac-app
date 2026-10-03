-- Tattiche e schemi: immagine (lavagna, screenshot) e spiegazione. Li pubblica il Direttivo.
create table if not exists public.tactics (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 80),
  module text check (module is null or char_length(module) <= 12),
  description text not null default '' check (char_length(description) <= 4000),
  image_path text,
  created_by uuid default auth.uid() references public.profiles on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.tactics enable row level security;
drop policy if exists "lettura membri" on public.tactics;
create policy "lettura membri" on public.tactics for select using (is_member());
drop policy if exists "scrittura direttivo" on public.tactics;
create policy "scrittura direttivo" on public.tactics for all
  using (is_direttivo()) with check (is_direttivo());

-- Immagini degli schemi: bucket privato, solo immagini fino a 5 MB.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('tactics', 'tactics', false, 5 * 1024 * 1024, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists "tattiche leggibili dai membri" on storage.objects;
create policy "tattiche leggibili dai membri" on storage.objects for select
  using (bucket_id = 'tactics' and is_member());
drop policy if exists "direttivo carica tattiche" on storage.objects;
create policy "direttivo carica tattiche" on storage.objects for all
  using (bucket_id = 'tactics' and is_direttivo())
  with check (bucket_id = 'tactics' and is_direttivo());
