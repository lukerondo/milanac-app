-- Preferenze delle notifiche (Impostazioni → Notifiche, ottobre 2026): ognuno può spegnere
-- "Presenze e promemoria", "Chat e stanze vocali" e "Notizie e aggiornamenti".
-- Una chiave mancante vale "attiva". Formazione, risultati, carte speciali e regolamento
-- arrivano sempre: sono le cose che il club deve poter dire a tutti.
alter table public.profiles
  add column if not exists notify_prefs jsonb not null default '{}'::jsonb;
alter table public.profiles drop constraint if exists profiles_notify_prefs_check;
alter table public.profiles add constraint profiles_notify_prefs_check
  check (jsonb_typeof(notify_prefs) = 'object' and pg_column_size(notify_prefs) <= 512);
