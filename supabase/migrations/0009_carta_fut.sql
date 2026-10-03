-- Carta FUT del giocatore: overall, stile di gioco e piattaforma.
-- Li scrive il giocatore sul proprio profilo; il Direttivo può correggerli.
alter table public.profiles
  add column if not exists overall smallint,
  add column if not exists play_style text,
  add column if not exists platform text;

alter table public.profiles drop constraint if exists profiles_overall_check;
alter table public.profiles add constraint profiles_overall_check
  check (overall is null or overall between 40 and 99);
alter table public.profiles drop constraint if exists profiles_play_style_check;
alter table public.profiles add constraint profiles_play_style_check
  check (play_style is null or char_length(play_style) <= 24);
alter table public.profiles drop constraint if exists profiles_platform_check;
alter table public.profiles add constraint profiles_platform_check
  check (platform is null or platform in ('ps5', 'xbox', 'pc'));
