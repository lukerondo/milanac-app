-- Regolamento ufficiale 2026 (novembre 2026): il documento del Direttivo diventa la bozza del
-- regolamento e una nuova versione pubblicata, come la pubblicherebbe publish_rules(); tutti i
-- membri dovranno leggerlo e accettarlo di nuovo. I "Cenni storici e identità" del documento
-- diventano la Storia del club. Nei testi il grassetto si scrive **così** (l'app lo mostra da
-- questa versione: le app vecchie fanno vedere gli asterischi).
-- Testi, grassetto e titoli degli articoli come nel documento, corretti negli errori di
-- battitura. Seguono il formato dell'app le righe in cima (MILANAC, MILANAC FUTURO, MILANO
-- SIAMO NOI, in grassetto una per riga, con il titolo del documento come titolo del primo
-- articolo) e l'organigramma: nel documento è una tabella, qui l'articolo "Organigramma" con
-- una riga "RUOLO: membri" per voce (l'app lo mostra come elenco e la Storia lo cerca con
-- questo titolo). Gli stessi testi stanno nella demo dell'app
-- (lib/features/regolamento/regolamento_2026.dart, un test controlla che coincidano).

-- La bozza: gli articoli del documento al posto di quelli di prima.
delete from public.rules_articles;
insert into public.rules_articles (sort_order, title, body) values
(0, 'Regolamento ufficiale 2026', $txt$**MILANAC**
**MILANAC FUTURO**
**MILANO SIAMO NOI**

“I nostri colori saranno il rosso, come il cuore che arde per la vittoria ed il nero come la notte che avvolgerà i sogni degli avversari. Saremo una legione infernale che danza sui campi di calcio virtuali, il nostro nome sarà MILANAC.”

**Se stai leggendo questo documento, significa che hai passato le selezioni e sei entrato nel MILANAC.** Il regolamento è stato creato per garantire il buon funzionamento della squadra, promuovere un ambiente positivo e competitivo, e massimizzare le nostre possibilità di successo. Tutti i membri sono tenuti a rispettare le regole presenti nel documento.$txt$),
(1, 'Organigramma', $txt$FONDATORI: Giuseppe Ruggieri, Fabio Ruggieri, Christian Rizzi
RESP. COMUNICAZIONI E MARKETING: Giuseppe Ruggieri
RESPONSABILE TECNICO / TATTICO: Fabio Ruggieri
RESPONSABILE RECLUTAMENTO: Fabiano Freduzzi
RESPONSABILE TORNEI E AMICHEVOLI: Vincenzo Lauricella
RESPONSABILE PRESENZE: Giovanni Giordano
RESPONSABILE IT: Francesco De Vietro$txt$),
(2, '1. Presenza e Comunicazione', $txt$**Disponibilità:** Le sessioni di allenamento, il campionato, i vari tornei e le amichevoli si tengono dal **LUNEDÌ AL VENERDÌ dalle ore 21:30 alle 23:30.**

Ogni giocatore deve comunicare la propria disponibilità tramite l'applicazione del MILANAC per le partite e gli allenamenti entro le ore 18:30.

In caso di assenza dopo aver segnato la presenza, il giocatore è tenuto a motivare la stessa al Responsabile della comunicazione che deciderà se accettare o meno la motivazione data.

**Formazione e Puntualità:** Il responsabile dello staff tecnico posterà la formazione di partenza sull'applicazione del MILANAC.

Ogni giocatore è tenuto a rispettare l'orario di convocazione.

Ogni ritardo (fatte salve eccezioni per gravi motivi) non sarà assolutamente accettato e considerato come una grave mancanza di rispetto verso il club ed i compagni di squadra; se reiterato, potrebbe portare all'esclusione dal Club.

**Tornei e Campionato:** I giocatori convocati per la partita sono tenuti a presentarsi in party 30 minuti prima dell'inizio della partita.

**Comunicazione Vocale:** L'uso della chat vocale è obbligatoriamente vietato **durante** le partite a chi non è autorizzato. La comunicazione è fondamentale per il coordinamento in campo e verrà effettuata solo ed esclusivamente dai responsabili tecnico-tattici preposti. Si richiede un atteggiamento rispettoso e costruttivo; in caso contrario, il giocatore che commette l'infrazione potrà essere ammonito o, alla peggio, espulso con conseguente non convocazione alla/e partita/e successiva/e per motivi disciplinari. Il microfono dovrà essere spento durante le partite.

**Canali Ufficiali del Club:** I canali ufficiali del club sono rispettivamente il party AC MILAN CLUB su PS5 ed il canale AC MILAN PRO CLUB sulla piattaforma Discord. Solo e soltanto staff e giocatori sono ammessi in questi canali.$txt$),
(3, '2. Comportamento e Disciplina', $txt$**Rispetto:** È fatto obbligo da parte di tutti i membri il rispetto reciproco, verso i propri compagni di squadra, verso il Direttivo e verso gli avversari. Comportamenti tossici, ineducati ed irrispettosi non verranno in alcun modo tollerati e saranno discussi molto seriamente dai fondatori della squadra.

**Accettazione delle Decisioni:** Le decisioni prese dai responsabili riguardo alla formazione, ai cambi ed alle tattiche da adottare sono insindacabili e quindi da accettare senza discussioni, agendo per il bene del club e della squadra. Le decisioni potranno eventualmente essere discusse privatamente con il Responsabile della Comunicazione.

**Analisi Tattica:** L'analisi tattica della squadra verrà tenuta dai responsabili il giorno seguente alla partita. I responsabili possono chiedere riunioni 1:1 con i singoli giocatori. Durante questi incontri i giocatori sono incoraggiati a fare domande e a fornire il loro feedback, rendendo il processo più interattivo e costruttivo.

**Gestione dei Conflitti:** In caso di problemi tra giocatori o all'interno del club, contattare il responsabile della comunicazione Giuseppe. Verranno eseguite tutte le procedure affinché venga garantito un trattamento equo per tutti i giocatori del club.$txt$),
(4, '3. Dinamiche di Gioco', $txt$**Ruoli e Tattiche:** Ogni giocatore deve impegnarsi a rispettare il proprio ruolo e le tattiche di squadra stabilite. **L'individualismo eccessivo a scapito del gioco di squadra sarà sanzionato**.

**Palle Inattive:** Le responsabilità sui calci d'angolo, punizioni e rigori, nonché il posizionamento dei giocatori in fase di non possesso, sono definite in anticipo dallo staff tecnico.

**Allenamento:** La partecipazione a sessioni di allenamento o amichevoli per migliorare l'affiatamento e provare nuove tattiche di gioco è obbligatoria. Coloro che saranno presenti agli allenamenti giocheranno le varie competizioni; chi salta gli allenamenti non per causa di forza maggiore potrà non essere convocato dallo staff tecnico.$txt$),
(5, '4. Gestione della Squadra e Sanzioni', $txt$**Suddivisione delle responsabilità:** Il presidente, il direttivo, il capitano ed il vice-capitano sono i responsabili della gestione della squadra ed hanno il compito di fare rispettare questo regolamento.

**Giocatori non Convocati:** Si incoraggia la presenza in party per supportare la squadra: siamo tutti un unico club.

**Sanzioni:** Le violazioni del regolamento possono portare a sanzioni, che vanno dall'esclusione temporanea dalla formazione titolare fino all'espulsione definitiva dalla squadra, a seconda della gravità e della frequenza delle infrazioni.$txt$),
(6, '5. Candidature Staff & Obiettivi', $txt$**Candidature Staff:** Ogni membro appartenente alla squadra potrà, dopo un periodo di 6 mesi dal suo ingresso, fare richiesta di candidatura all'interno dello staff del club, suggerendo nuovi ruoli che saranno discussi dai membri del Direttivo.

TUTTI quanti i membri del club sono FONDAMENTALI per la riuscita del progetto. Si cresce tutti assieme.

**Obiettivi e Visione del Club:** L’ambizione del Club è quella di affermarsi ed essere riconosciuto all'interno delle competizioni nazionali ed internazionali come un gruppo solido di amici, rispettoso delle regole, elegante, ed essere rispettato dagli avversari. Per far sì che ciò avvenga, ogni giocatore del club dovrà ricordare che l'ID che porta sulla maglia è meno importante del club e dello stemma che rappresenta.

Il MILANAC Pro Club punta ad affermarsi come una solida realtà all'interno della comunità ESPORTS, partecipando sempre per vincere e divertirsi alle varie competizioni alle quali prenderà parte, con stile e classe.

**BENVENUTO IN FAMIGLIA!**$txt$);

-- La nuova versione, con la stessa fotografia di publish_rules(). Nessuno la pubblica dall'app
-- (published_by vuoto, come la versione 1 della 0016): nessuno risulta averla già accettata.
-- Se l'ultima versione è già questa (migrazione rilanciata) non se ne crea un'altra.
do $$
declare
  snap jsonb := (select jsonb_agg(jsonb_build_object('title', a.title, 'body', a.body)
                                  order by a.sort_order, a.updated_at)
                 from public.rules_articles a);
  n int;
begin
  if snap is not distinct from
     (select snapshot from public.rules_versions order by number desc limit 1) then
    return;
  end if;
  insert into public.rules_versions (number, snapshot, published_by)
  values (coalesce((select max(number) from public.rules_versions), 0) + 1, snap, null)
  returning number into n;
  -- La notifica a tutti i membri, come publish_rules() (senza la funzione notify non parte).
  perform public.notify_push(jsonb_build_object('kind', 'rules', 'version', n));
end $$;

-- La storia del club: la citazione del documento e i cenni storici.
insert into public.pages (slug, content, updated_by, updated_at) values ('storia',
$txt$“I nostri colori saranno il rosso, come il cuore che arde per la vittoria ed il nero come la notte che avvolgerà i sogni degli avversari. Saremo una legione infernale che danza sui campi di calcio virtuali, il nostro nome sarà MILANAC.”

Il club nasce nel 2025 da un'idea di Fabio Ruggieri, Giuseppe Ruggieri e Christian Rizzi. La missione del Club si basa su una condizione fondamentale, quella di tesserare solamente giocatori che tifino per l'AC MILAN. Il nostro nome si ispira alla squadra che tifiamo, volendolo tenere il più fedele possibile all'originale. I colori sociali della squadra sono il rosso, il nero ed il bianco.$txt$, null, now())
on conflict (slug) do update
  set content = excluded.content, updated_by = null, updated_at = excluded.updated_at;
