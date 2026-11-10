// Notifiche nel browser: poche funzioni sopra Web Push per l'app (Dart), che le chiama da
// lib/core/push/web_push_web.dart. Il messaggio lo riceve notifiche-sw.js anche ad app
// chiusa; qui si chiede il permesso, si iscrive questo browser con la chiave pubblica
// del club e si passano all'app gli avvisi che arrivano mentre è aperta.
(function () {
  'use strict';

  var SW = 'notifiche-sw.js';
  // Ambito tutto suo: quello dell'app lo usa Flutter (vedi notifiche-sw.js).
  var AMBITO = 'notifiche/';
  var ascoltatore = null;
  // Avvisi arrivati prima che l'app fosse pronta ad ascoltare.
  var inAttesa = [];

  function supportate() {
    return window.isSecureContext && 'serviceWorker' in navigator &&
      'PushManager' in window && 'Notification' in window;
  }

  // iPhone e iPad ricevono le notifiche solo dall'app aggiunta alla schermata Home.
  function daInstallare() {
    var apple = /iPhone|iPad|iPod/.test(navigator.userAgent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    return apple && navigator.standalone !== true;
  }

  // 'non_supportate', 'da_installare', 'da_chiedere', 'negate' oppure 'concesse'.
  function stato() {
    if (!supportate()) return daInstallare() ? 'da_installare' : 'non_supportate';
    if (Notification.permission === 'granted') return 'concesse';
    return Notification.permission === 'denied' ? 'negate' : 'da_chiedere';
  }

  function indirizzo(file) {
    return new URL(file, document.baseURI).href;
  }

  function b64url(buffer) {
    var bytes = new Uint8Array(buffer);
    var s = '';
    for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return btoa(s).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
  }

  function daB64url(testo) {
    var s = testo.replace(/-/g, '+').replace(/_/g, '/');
    while (s.length % 4) s += '=';
    var bin = atob(s);
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  }

  function sigla(e) {
    return String((e && (e.message && /^[A-Z_]+$/.test(e.message) ? e.message : e.name)) || 'ERRORE');
  }

  // Il service worker registrato e già attivo (l'iscrizione lo vuole attivo).
  function registrazione() {
    return navigator.serviceWorker
      .register(indirizzo(SW), { scope: indirizzo(AMBITO), updateViaCache: 'none' })
      .then(function (reg) {
        if (reg.active) return reg;
        var sw = reg.installing || reg.waiting;
        if (!sw) throw new Error('SW_ASSENTE');
        return new Promise(function (ok, no) {
          function guarda() {
            if (sw.state === 'activated') ok(reg);
            else if (sw.state === 'redundant') no(new Error('SW_ASSENTE'));
          }
          sw.addEventListener('statechange', guarda);
          guarda();
        });
      });
  }

  function registrata() {
    return navigator.serviceWorker.getRegistration(indirizzo(AMBITO));
  }

  function permesso() {
    if (Notification.permission === 'granted') return Promise.resolve('granted');
    return new Promise(function (ok) {
      // I Safari più vecchi rispondono con la funzione, gli altri con la promessa.
      var r = Notification.requestPermission(ok);
      if (r && r.then) r.then(ok, function () { ok(Notification.permission); });
    });
  }

  function dati(sub) {
    return {
      errore: '',
      endpoint: sub.endpoint,
      p256dh: b64url(sub.getKey('p256dh')),
      auth: b64url(sub.getKey('auth')),
    };
  }

  function vuota(errore) {
    return { errore: errore, endpoint: '', p256dh: '', auth: '' };
  }

  function stessaChiave(sub, pubblica) {
    var k = sub.options && sub.options.applicationServerKey;
    // Se il browser non la dice, si tiene l'iscrizione che c'è.
    return !k || b64url(k) === pubblica;
  }

  // Senza rete il browser può restare in attesa del servizio push: oltre [ms] si rinuncia.
  function entro(promessa, ms) {
    return new Promise(function (ok, no) {
      var t = setTimeout(function () { no(new Error('TEMPO')); }, ms);
      promessa.then(
        function (v) { clearTimeout(t); ok(v); },
        function (e) { clearTimeout(t); no(e); });
    });
  }

  function iscrivi(pubblica) {
    return registrazione().then(function (reg) {
      return reg.pushManager.getSubscription().then(function (sub) {
        if (sub && stessaChiave(sub, pubblica)) return sub;
        // Chiavi del club cambiate: l'iscrizione vecchia non riceverebbe più niente.
        var via = sub ? sub.unsubscribe() : Promise.resolve();
        return via.then(function () {
          return reg.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: daB64url(pubblica),
          });
        });
      });
    });
  }

  // Chiede il permesso (va chiamata dal clic: il permesso è la prima cosa che fa) e
  // iscrive questo browser con la chiave pubblica del club. Risponde sempre:
  // { errore: '' , endpoint, p256dh, auth } oppure { errore: 'SIGLA', ... }.
  function attiva(pubblica) {
    if (!supportate()) return Promise.resolve(vuota('NON_SUPPORTATE'));
    // La risposta alla richiesta del browser non ha fretta; l'iscrizione sì.
    return permesso().then(function (p) {
      if (p !== 'granted') throw new Error(p === 'denied' ? 'NEGATE' : 'NON_CONCESSE');
      return entro(iscrivi(pubblica), 20000);
    }).then(dati, function (e) { return vuota(sigla(e)); });
  }

  // L'iscrizione che questo browser ha già (senza chiedere niente), o endpoint vuoto.
  function iscrizione() {
    if (!supportate()) return Promise.resolve(vuota(''));
    return registrata().then(function (reg) {
      return reg ? reg.pushManager.getSubscription() : null;
    }).then(function (sub) {
      return sub ? dati(sub) : vuota('');
    }, function (e) { return vuota(sigla(e)); });
  }

  // Toglie l'iscrizione di questo browser. Risponde con l'indirizzo che aveva ('' se
  // non c'era): serve a cancellarla anche sul server.
  function disattiva() {
    if (!supportate()) return Promise.resolve('');
    return registrata().then(function (reg) {
      return reg ? reg.pushManager.getSubscription() : null;
    }).then(function (sub) {
      if (!sub) return '';
      var endpoint = sub.endpoint;
      return sub.unsubscribe().then(function () { return endpoint; }, function () { return endpoint; });
    }, function () { return ''; });
  }

  // L'app ascolta gli avvisi del service worker: 'notifica' (messaggio arrivato con l'app
  // davanti), 'apri' (clic su una notifica), 'iscrizione' (rinnovata dal browser).
  function ascolta(fn) {
    ascoltatore = fn;
    var coda = inAttesa;
    inAttesa = [];
    coda.forEach(consegna);
  }

  function consegna(m) {
    if (!ascoltatore) {
      if (inAttesa.length < 20) inAttesa.push(m);
      return;
    }
    try {
      ascoltatore(
        String(m.milanac), String(m.title || ''), String(m.body || ''), String(m.route || ''),
        JSON.stringify(m.data && typeof m.data === 'object' ? m.data : {}));
    } catch (e) { /* l'app non è pronta: l'avviso si perde, la notifica no */ }
  }

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', function (event) {
      var m = event.data;
      // Solo dal nostro service worker (stessa origine per costruzione) e solo i nostri avvisi.
      if (m && typeof m === 'object' && typeof m.milanac === 'string') consegna(m);
    });
    if (navigator.serviceWorker.startMessages) navigator.serviceWorker.startMessages();
  }

  window.milanacNotifiche = {
    stato: stato,
    attiva: attiva,
    iscrizione: iscrizione,
    disattiva: disattiva,
    ascolta: ascolta,
  };
})();
