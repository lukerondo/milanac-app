-- Carte FUT con la foto vera (ottobre 2026). Le carte diventano come quelle di FUT: sei
-- statistiche (VEL TIR PAS DRI DIF FIS; per i portieri TUF PRE RIN RIF VEL PIA) che
-- inserisce il giocatore stesso o il Direttivo, e come immagine solo la foto caricata
-- dalla galleria (avatar_path, già nel bucket "avatars"). Il volto disegnato non si usa
-- più: la colonna face e il parametro p_face di complete_registration restano solo per
-- le app non ancora aggiornate.

-- Le statistiche: un oggetto con le chiavi note e valori interi da 1 a 99. Quelle da
-- portiere stanno a parte, così cambiando ruolo non si perde niente.
create or replace function public.valid_fut_stats(s jsonb) returns boolean
language sql immutable as $$
  select case
    when s is null then false
    when jsonb_typeof(s) <> 'object' then false
    else not exists (
      select 1 from jsonb_each(s) e
      where e.key not in ('pac', 'sho', 'pas', 'dri', 'def', 'phy',
                          'div', 'han', 'kic', 'ref', 'spd', 'pos')
         or case
              when jsonb_typeof(e.value) <> 'number' then true
              else (e.value)::numeric not between 1 and 99
                or (e.value)::numeric <> trunc((e.value)::numeric)
            end
    )
  end
$$;

alter table public.profiles
  add column if not exists fut_stats jsonb not null default '{}'::jsonb;
alter table public.profiles drop constraint if exists profiles_fut_stats_valid;
alter table public.profiles
  add constraint profiles_fut_stats_valid check (public.valid_fut_stats(fut_stats));

-- Nessun permesso nuovo: come gli altri campi della carta, le statistiche le modifica il
-- giocatore sul proprio profilo ("modifica proprio profilo") e il Direttivo su tutti;
-- l'overall resta del solo Direttivo (prevent_self_role_change).
