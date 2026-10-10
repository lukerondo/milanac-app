-- Regolamento d'ingresso (ottobre 2026): se non c'è ancora una versione pubblicata nessuno
-- resta bloccato alla pagina del regolamento. Chi ha completato la registrazione entra con
-- enter_club(); il primo del Direttivo che entra scrive e pubblica il regolamento e da quel
-- momento tutti lo leggono e lo accettano. Chi pubblica lo ha già letto: gli risulta accettato.

-- Ingresso senza regolamento: il profilo prende il ruolo richiesto, come farebbe accept_rules.
create or replace function public.enter_club() returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  done timestamptz;
begin
  if uid is null then
    raise exception 'Non autenticato';
  end if;
  if exists (select 1 from rules_versions) then
    raise exception 'C''è un regolamento da accettare';
  end if;
  select registration_completed_at into done from profiles where id = uid;
  if done is null then
    raise exception 'Completa prima la registrazione';
  end if;
  perform set_config('milanac.registration', '1', true);
  update profiles set
    club_role = case when club_role = 'pending' then requested_role else club_role end
  where id = uid;
end $$;
revoke all on function public.enter_club() from public, anon;
grant execute on function public.enter_club() to authenticated;

-- Pubblicazione: come prima, ma chi pubblica non deve riaccettare quello che ha scritto.
create or replace function public.publish_rules() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_direttivo() then
    raise exception 'Solo il Direttivo può pubblicare il regolamento';
  end if;
  if not exists (select 1 from rules_articles) then
    raise exception 'Scrivi almeno un articolo';
  end if;
  insert into rules_versions (number, snapshot, published_by)
  values (
    coalesce((select max(number) from rules_versions), 0) + 1,
    (select jsonb_agg(jsonb_build_object('title', a.title, 'body', a.body) order by a.sort_order, a.updated_at)
       from rules_articles a),
    auth.uid())
  returning number into n;
  perform set_config('milanac.registration', '1', true);
  update profiles set rules_accepted_version = n, rules_accepted_at = now() where id = auth.uid();
  perform notify_push(jsonb_build_object('kind', 'rules', 'version', n));
  return n;
end $$;

-- Permessi espliciti (di norma già dati dai privilegi predefiniti di Supabase): le versioni
-- le legge chi è autenticato, la bozza solo il Direttivo (policy).
grant select on public.rules_versions to authenticated;
grant select, insert, update, delete on public.rules_articles to authenticated;
