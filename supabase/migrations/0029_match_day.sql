-- Match Day (ottobre 2026): il codice del party della partita. Lo scrive il Direttivo e lo
-- vedono tutti nella card della serata in Home, con il conto alla rovescia.
alter table public.events add column if not exists party_code text;
alter table public.events drop constraint if exists events_party_code_len;
alter table public.events add constraint events_party_code_len
  check (party_code is null or char_length(btrim(party_code)) between 1 and 40);
