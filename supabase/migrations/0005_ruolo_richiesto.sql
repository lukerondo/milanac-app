-- Al primo accesso il nuovo utente indica se chiede di entrare come Giocatore o Direttivo.
-- Il ruolo vero (club_role) lo assegna sempre il Direttivo approvando la richiesta.
alter table public.profiles
  add column if not exists requested_role club_role not null default 'giocatore';

alter table public.profiles drop constraint if exists profiles_requested_role_check;
alter table public.profiles
  add constraint profiles_requested_role_check check (requested_role in ('direttivo', 'giocatore'));
