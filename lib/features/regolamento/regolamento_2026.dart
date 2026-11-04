/// Il Regolamento ufficiale 2026 e la storia del club, dal documento del Direttivo
/// (novembre 2026), corretti solo negli errori di battitura. In produzione arrivano con la
/// migrazione 0033; qui li usano la demo e i test (un test controlla che coincidano).
library;

/// Gli articoli in ordine: grassetto con **testo**, paragrafi separati da una riga
/// vuota; l'organigramma ha una riga "ETICHETTA: valore" per ruolo (diventa un elenco).
const regolamento2026 = <({String title, String body})>[
  (
    title: 'Regolamento ufficiale 2026',
    body:
        'MILANAC · MILANAC FUTURO\n'
        'Milano siamo noi\n\n'
        '“I nostri colori saranno il rosso, come il cuore che arde per '
        'la vittoria ed il nero come la notte che avvolgerà i sogni '
        'degli avversari. Saremo una legione infernale che danza sui '
        'campi di calcio virtuali, il nostro nome sarà MILANAC.”\n\n'
        '**Se stai leggendo questo documento, significa che hai passato '
        'le selezioni e sei entrato nel MILANAC.** Il regolamento è '
        'stato creato per garantire il buon funzionamento della squadra, '
        'promuovere un ambiente positivo e competitivo, e massimizzare '
        'le nostre possibilità di successo. Tutti i membri sono tenuti a '
        'rispettare le regole presenti nel documento.',
  ),
  (
    title: 'Organigramma',
    body:
        'FONDATORI: Giuseppe Ruggieri, Fabio Ruggieri, Christian Rizzi\n'
        'RESP. COMUNICAZIONI E MARKETING: Giuseppe Ruggieri\n'
        'RESPONSABILE TECNICO / TATTICO: Fabio Ruggieri\n'
        'RESPONSABILE RECLUTAMENTO: Fabiano Freduzzi\n'
        'RESPONSABILE TORNEI E AMICHEVOLI: Vincenzo Lauricella\n'
        'RESPONSABILE PRESENZE: Giovanni Giordano\n'
        'RESPONSABILE IT: Francesco De Vietro',
  ),
  (
    title: 'Art. 1 – Presenza e comunicazione',
    body:
        '**Disponibilità:** Le sessioni di allenamento, il campionato, i '
        'vari tornei e le amichevoli si tengono dal LUNEDÌ AL VENERDÌ '
        'dalle ore 21:30 alle 23:30.\n\n'
        'Ogni giocatore deve comunicare la propria disponibilità tramite '
        "l'applicazione del MILANAC per le partite e gli allenamenti "
        'entro le ore 18:30.\n\n'
        'In caso di assenza dopo aver segnato la presenza, il giocatore '
        'è tenuto a motivare la stessa al Responsabile della '
        'comunicazione che deciderà se accettare o meno la motivazione '
        'data.\n\n'
        '**Formazione e Puntualità:** Il responsabile dello staff '
        "tecnico posterà la formazione di partenza sull'applicazione del "
        'MILANAC.\n\n'
        "Ogni giocatore è tenuto a rispettare l'orario di convocazione.\n\n"
        'Ogni ritardo (fatte salve eccezioni per gravi motivi) non sarà '
        'assolutamente accettato e considerato come una grave mancanza '
        'di rispetto verso il club ed i compagni di squadra; se '
        "reiterato, potrebbe portare all'esclusione dal Club.\n\n"
        '**Tornei e Campionato:** I giocatori convocati per la partita '
        "sono tenuti a presentarsi in party 30 minuti prima dell'inizio "
        'della partita.\n\n'
        "**Comunicazione Vocale:** L'uso della chat vocale è "
        'obbligatoriamente vietato **durante** le partite a chi non è '
        'autorizzato. La comunicazione è fondamentale per il '
        'coordinamento in campo e verrà effettuata solo ed '
        'esclusivamente dai responsabili tecnico-tattici preposti. Si '
        'richiede un atteggiamento rispettoso e costruttivo; in caso '
        "contrario, il giocatore che commette l'infrazione potrà essere "
        'ammonito o, alla peggio, espulso con conseguente non '
        'convocazione alla/e partita/e successiva/e per motivi '
        'disciplinari. Il microfono dovrà essere spento durante le '
        'partite.\n\n'
        '**Canali Ufficiali del Club:** I canali ufficiali del club sono '
        'rispettivamente il party AC MILAN CLUB su PS5 ed il canale AC '
        'MILAN PRO CLUB sulla piattaforma Discord. Solo e soltanto staff '
        'e giocatori sono ammessi in questi canali.',
  ),
  (
    title: 'Art. 2 – Comportamento e disciplina',
    body:
        '**Rispetto:** È fatto obbligo da parte di tutti i membri il '
        'rispetto reciproco, verso i propri compagni di squadra, verso '
        'il Direttivo e verso gli avversari. Comportamenti tossici, '
        'ineducati ed irrispettosi non verranno in alcun modo tollerati '
        'e saranno discussi molto seriamente dai fondatori della '
        'squadra.\n\n'
        '**Accettazione delle Decisioni:** Le decisioni prese dai '
        'responsabili riguardo alla formazione, ai cambi ed alle '
        'tattiche da adottare sono insindacabili e quindi da accettare '
        'senza discussioni, agendo per il bene del club e della squadra. '
        'Le decisioni potranno eventualmente essere discusse '
        'privatamente con il Responsabile della Comunicazione.\n\n'
        "**Analisi Tattica:** L'analisi tattica della squadra verrà "
        'tenuta dai responsabili il giorno seguente alla partita. I '
        'responsabili possono chiedere riunioni 1:1 con i singoli '
        'giocatori. Durante questi incontri i giocatori sono '
        'incoraggiati a fare domande e a fornire il loro feedback, '
        'rendendo il processo più interattivo e costruttivo.\n\n'
        '**Gestione dei Conflitti:** In caso di problemi tra giocatori o '
        "all'interno del club, contattare il responsabile della "
        'comunicazione Giuseppe. Verranno eseguite tutte le procedure '
        'affinché venga garantito un trattamento equo per tutti i '
        'giocatori del club.',
  ),
  (
    title: 'Art. 3 – Dinamiche di gioco',
    body:
        '**Ruoli e Tattiche:** Ogni giocatore deve impegnarsi a '
        'rispettare il proprio ruolo e le tattiche di squadra stabilite. '
        "**L'individualismo eccessivo a scapito del gioco di squadra "
        'sarà sanzionato**.\n\n'
        "**Palle Inattive:** Le responsabilità sui calci d'angolo, "
        'punizioni e rigori, nonché il posizionamento dei giocatori in '
        'fase di non possesso, sono definite in anticipo dallo staff '
        'tecnico.\n\n'
        '**Allenamento:** La partecipazione a sessioni di allenamento o '
        "amichevoli per migliorare l'affiatamento e provare nuove "
        'tattiche di gioco è obbligatoria. Coloro che saranno presenti '
        'agli allenamenti giocheranno le varie competizioni; chi salta '
        'gli allenamenti non per causa di forza maggiore potrà non '
        'essere convocato dallo staff tecnico.',
  ),
  (
    title: 'Art. 4 – Gestione della squadra e sanzioni',
    body:
        '**Suddivisione delle responsabilità:** Il presidente, il '
        'direttivo, il capitano ed il vice-capitano sono i responsabili '
        'della gestione della squadra ed hanno il compito di fare '
        'rispettare questo regolamento.\n\n'
        '**Giocatori non Convocati:** Si incoraggia la presenza in party '
        'per supportare la squadra: siamo tutti un unico club.\n\n'
        '**Sanzioni:** Le violazioni del regolamento possono portare a '
        "sanzioni, che vanno dall'esclusione temporanea dalla formazione "
        "titolare fino all'espulsione definitiva dalla squadra, a "
        'seconda della gravità e della frequenza delle infrazioni.',
  ),
  (
    title: 'Art. 5 – Candidature staff e obiettivi',
    body:
        '**Candidature Staff:** Ogni membro appartenente alla squadra '
        'potrà, dopo un periodo di 6 mesi dal suo ingresso, fare '
        "richiesta di candidatura all'interno dello staff del club, "
        'suggerendo nuovi ruoli che saranno discussi dai membri del '
        'Direttivo.\n\n'
        'TUTTI quanti i membri del club sono FONDAMENTALI per la '
        'riuscita del progetto. Si cresce tutti assieme.\n\n'
        "**Obiettivi e Visione del Club:** L'ambizione del Club è quella "
        "di affermarsi ed essere riconosciuto all'interno delle "
        'competizioni nazionali ed internazionali come un gruppo solido '
        'di amici, rispettoso delle regole, elegante, ed essere '
        'rispettato dagli avversari. Per far sì che ciò avvenga, ogni '
        "giocatore del club dovrà ricordare che l'ID che porta sulla "
        'maglia è meno importante del club e dello stemma che '
        'rappresenta.\n\n'
        'Il MILANAC Pro Club punta ad affermarsi come una solida realtà '
        "all'interno della comunità ESPORTS, partecipando sempre per "
        'vincere e divertirsi alle varie competizioni alle quali '
        'prenderà parte, con stile e classe.\n\n'
        '**BENVENUTO IN FAMIGLIA!**',
  ),
];

/// La storia del club (pagina "storia"): la citazione e i cenni storici del documento.
const storia2026 =
    '“I nostri colori saranno il rosso, come il cuore che arde per '
    'la vittoria ed il nero come la notte che avvolgerà i sogni '
    'degli avversari. Saremo una legione infernale che danza sui '
    'campi di calcio virtuali, il nostro nome sarà MILANAC.”\n\n'
    "Il club nasce nel 2025 da un'idea di Fabio Ruggieri, Giuseppe "
    'Ruggieri e Christian Rizzi. La missione del Club si basa su una '
    'condizione fondamentale, quella di tesserare solamente '
    "giocatori che tifino per l'AC MILAN. Il nostro nome si ispira "
    'alla squadra che tifiamo, volendolo tenere il più fedele '
    "possibile all'originale. I colori sociali della squadra sono il "
    'rosso, il nero ed il bianco.';
