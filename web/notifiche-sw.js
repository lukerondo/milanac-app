// Notifiche della web app (Web Push). Lo registra notifiche.js con un ambito tutto suo
// (notifiche/): quello dell'app resta libero, lo usa Flutter per i suoi file.
//
// Il messaggio arriva cifrato dalla funzione notify di Supabase (supabase/functions/notify)
// ed è un JSON: { title, body, route, data }. Se l'app è aperta e davanti agli occhi,
// l'avviso lo mostra lei (in basso nella pagina); altrimenti esce la notifica di sistema
// e il clic porta alla sezione indicata da route.
'use strict';

// La cartella dell'app (…/app/): questo file sta lì.
var APP = new URL('./', self.location.href).href;

self.addEventListener('install', function () {
  self.skipWaiting();
});

// Le finestre dell'app aperte in questo browser (non le controlla questo service worker:
// vanno cercate tra tutte quelle del sito).
function finestre() {
  return self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (tutte) {
    return tutte.filter(function (c) { return c.url.indexOf(APP) === 0; });
  });
}

// Safari toglie l'iscrizione a chi riceve un messaggio senza mostrare la notifica, anche
// con la pagina aperta: lì la notifica di sistema esce sempre.
function servizioApple() {
  return self.registration.pushManager.getSubscription().then(function (sub) {
    try {
      return !!sub && /(^|\.)push\.apple\.com$/.test(new URL(sub.endpoint).hostname);
    } catch (e) {
      return false;
    }
  }, function () { return false; });
}

function leggi(event) {
  var m = {};
  try { m = event.data ? event.data.json() : {}; } catch (e) { m = {}; }
  if (!m || typeof m !== 'object') m = {};
  return {
    title: typeof m.title === 'string' && m.title ? m.title : 'MILANAC Pro Club',
    body: typeof m.body === 'string' ? m.body : '',
    // Solo sezioni dell'app: mai un indirizzo esterno.
    route: typeof m.route === 'string' && m.route.charAt(0) === '/' && m.route.charAt(1) !== '/'
      ? m.route : '/',
    data: m.data && typeof m.data === 'object' ? m.data : {},
  };
}

self.addEventListener('push', function (event) {
  var m = leggi(event);
  event.waitUntil((async function () {
    if (!(await servizioApple())) {
      var davanti = (await finestre()).filter(function (c) {
        return c.focused && c.visibilityState === 'visible';
      });
      if (davanti.length > 0) {
        davanti.forEach(function (c) {
          c.postMessage({ milanac: 'notifica', title: m.title, body: m.body, route: m.route, data: m.data });
        });
        return;
      }
    }
    await self.registration.showNotification(m.title, {
      body: m.body,
      icon: APP + 'icons/Icon-192.png',
      badge: APP + 'icons/notifica.png',
      lang: 'it',
      // Una notifica per sezione: dieci messaggi nello stesso canale non ne fanno dieci.
      tag: m.route,
      renotify: true,
      data: { route: m.route },
    });
  })());
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var dati = event.notification.data || {};
  var route = typeof dati.route === 'string' && dati.route.charAt(0) === '/' ? dati.route : '/';
  event.waitUntil((async function () {
    var aperte = await finestre();
    var finestra = aperte.filter(function (c) { return c.focused; })[0] || aperte[0];
    if (finestra) {
      try { finestra = (await finestra.focus()) || finestra; } catch (e) { /* resta dov'è */ }
      finestra.postMessage({ milanac: 'apri', route: route });
      return;
    }
    await self.clients.openWindow(APP + '#' + route);
  })());
});

// Il browser ha cambiato l'iscrizione (succede di rado): la rinnova con le stesse chiavi
// e lo dice all'app aperta, che la registra di nuovo. Se l'app è chiusa ci pensa alla
// prossima apertura.
self.addEventListener('pushsubscriptionchange', function (event) {
  event.waitUntil((async function () {
    try {
      var opzioni = event.oldSubscription && event.oldSubscription.options;
      if (!event.newSubscription && opzioni) {
        await self.registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: opzioni.applicationServerKey,
        });
      }
    } catch (e) { /* alla prossima apertura dell'app */ }
    (await finestre()).forEach(function (c) { c.postMessage({ milanac: 'iscrizione' }); });
  })());
});
