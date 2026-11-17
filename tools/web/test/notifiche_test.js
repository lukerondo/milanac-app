// Prova nel browser vero di web/notifiche.js e web/notifiche-sw.js: registrazione del
// service worker nel suo ambito, messaggio push con l'app davanti (lo riceve la pagina),
// con l'app dietro (notifica di sistema) e clic sulla notifica (si apre la sezione).
// Il messaggio lo consegna il debugger di Chrome: non serve un servizio push vero.
//
//   node tools/web/test/notifiche_test.js
//
// Usa Playwright (playwright-core va bene) e Chrome: CHROME_CHANNEL=chrome per quello
// installato, altrimenti il Chromium di Playwright.
// SENZA_CENTRO_NOTIFICHE=1 prova anche il caso di un sistema che non tiene le notifiche.
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const assert = require('assert');

let chromium;
try {
  ({ chromium } = require('playwright-core'));
} catch (e) {
  ({ chromium } = require('playwright'));
}

const WEB = path.join(__dirname, '..', '..', '..', 'web');
const TIPI = { '.js': 'text/javascript', '.png': 'image/png', '.json': 'application/json' };

// Il sito in piccolo: l'app sta sotto /app/ come online.
function sito() {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname === '/app/') {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      return res.end('<!doctype html><base href="/app/"><title>prova</title>' +
        '<script src="notifiche.js"></script>');
    }
    if (url.pathname === '/altrove') {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      return res.end('<!doctype html><title>altrove</title>');
    }
    const file = path.join(WEB, url.pathname.replace(/^\/app\//, ''));
    if (!url.pathname.startsWith('/app/') || !file.startsWith(WEB) || !fs.existsSync(file)) {
      res.writeHead(404);
      return res.end();
    }
    res.writeHead(200, { 'Content-Type': TIPI[path.extname(file)] || 'application/octet-stream' });
    res.end(fs.readFileSync(file));
  });
  return new Promise((ok) => server.listen(0, '127.0.0.1', () => ok(server)));
}

// Sul runner di CI il service worker può metterci qualche secondo a ripartire.
async function aspetta(cosa, leggi, ms = 20000) {
  const fine = Date.now() + ms;
  for (;;) {
    const v = await leggi();
    if (v) return v;
    if (Date.now() > fine) throw new Error('Non è successo in tempo: ' + cosa);
    await new Promise((ok) => setTimeout(ok, 50));
  }
}

(async () => {
  const server = await sito();
  const origine = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({
    // 'chromium' (o 'chrome'): il browser intero, anche senza finestra. Quello ridotto
    // di Playwright non ha le notifiche.
    channel: process.env.CHROME_CHANNEL || 'chromium',
    executablePath: process.env.CHROME_EXECUTABLE || undefined,
    args: ['--no-sandbox'],
  });
  try {
    console.log('Browser:', browser.version());
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(origine + '/app/');

    // 1. Senza permesso (Chrome senza finestra le dà per negate): nessuna iscrizione,
    //    nessun service worker.
    assert.match(await page.evaluate(() => milanacNotifiche.stato()), /^(da_chiedere|negate)$/);
    assert.deepStrictEqual(
      await page.evaluate(() => milanacNotifiche.iscrizione()),
      { errore: '', endpoint: '', p256dh: '', auth: '' });
    assert.strictEqual(await page.evaluate(() => milanacNotifiche.disattiva()), '');

    // 2. Con il permesso: il service worker si registra nel suo ambito ed è attivo.
    //    L'iscrizione vera vuole il servizio push di Google, che qui può mancare: in quel
    //    caso la risposta è una sigla d'errore, mai un'eccezione.
    await context.grantPermissions(['notifications'], { origin: origine });
    assert.strictEqual(await page.evaluate(() => milanacNotifiche.stato()), 'concesse');
    const chiave = 'BFVRA0VTzVDPMxpZvxGTqkDnYG9yXcnI-2HlmSkmVDDSyqR8Hn6Ae8fMEtu3Un4gF3FAJB8gk4ia4Fzo5yT7zCQ';
    const esito = await page.evaluate((k) => milanacNotifiche.attiva(k), chiave);
    assert.deepStrictEqual(Object.keys(esito).sort(), ['auth', 'endpoint', 'errore', 'p256dh']);
    if (esito.errore) {
      assert.match(esito.errore, /^[A-Za-z_]+$/);
      assert.strictEqual(esito.endpoint, '');
    } else {
      assert.match(esito.endpoint, /^https:\/\//);
      assert.match(esito.p256dh, /^[A-Za-z0-9_-]{87}$/);
      assert.match(esito.auth, /^[A-Za-z0-9_-]{22}$/);
    }
    const reg = await page.evaluate(async () => {
      const r = await navigator.serviceWorker.getRegistration(new URL('notifiche/', document.baseURI).href);
      return r && { scope: r.scope, attivo: !!r.active, script: r.active && r.active.scriptURL };
    });
    assert.deepStrictEqual(reg, {
      scope: origine + '/app/notifiche/', attivo: true, script: origine + '/app/notifiche-sw.js',
    });
    // L'ambito dell'app resta libero per Flutter.
    assert.strictEqual(
      await page.evaluate(async () => !!(await navigator.serviceWorker.getRegistration(document.baseURI))),
      false);

    // Il debugger consegna i messaggi push a quel service worker.
    const cdp = await context.newCDPSession(page);
    await cdp.send('ServiceWorker.enable');
    const versioni = [];
    cdp.on('ServiceWorker.workerRegistrationUpdated', (e) => versioni.push(...e.registrations));
    const registrazione = await aspetta('registrazione vista dal debugger', () =>
      versioni.find((r) => r.scopeURL === origine + '/app/notifiche/'));
    const push = (dati) => cdp.send('ServiceWorker.deliverPushMessage', {
      origin: origine, registrationId: registrazione.registrationId, data: JSON.stringify(dati),
    });
    const sw = context.serviceWorkers().find((w) => w.url().endsWith('/notifiche-sw.js')) ||
      await context.waitForEvent('serviceworker');
    // Quello che il service worker chiede al sistema di mostrare si registra qui: la prova
    // guarda le sue decisioni e non dipende da dove Chrome tiene le notifiche (cambia da
    // una versione all'altra, e sui server di prova il centro notifiche può mancare).
    await sw.evaluate((senzaCentro) => {
      self.__chieste = [];
      self.__errori = [];
      // SENZA_CENTRO_NOTIFICHE=1: come un sistema che le notifiche non le sa tenere.
      if (senzaCentro) {
        self.registration.getNotifications = async () => [];
        self.registration.showNotification = async () => {
          throw new DOMException('centro notifiche assente', 'NotSupportedError');
        };
      }
      const vera = self.registration.showNotification.bind(self.registration);
      self.registration.showNotification = function (title, o) {
        o = o || {};
        self.__chieste.push({
          title, body: o.body, tag: o.tag, data: o.data, icon: o.icon, renotify: o.renotify,
        });
        return vera(title, o).catch((e) => {
          self.__errori.push(String(e && e.name) + ': ' + String(e && e.message));
        });
      };
    }, process.env.SENZA_CENTRO_NOTIFICHE === '1');
    const stato = () => sw.evaluate(async () => ({
      chieste: self.__chieste,
      errori: self.__errori,
      permesso: Notification.permission,
      finestre: (await self.clients.matchAll({ type: 'window', includeUncontrolled: true }))
        .map((c) => ({ url: c.url, davanti: c.focused, vista: c.visibilityState })),
      sistema: (await self.registration.getNotifications())
        .map((n) => ({ title: n.title, body: n.body, tag: n.tag })),
    }));
    // Aspetta una notifica chiesta dal service worker; se non arriva dice che cosa vedeva.
    const chiesta = (cosa, prova) => aspetta(cosa, async () =>
      (await stato()).chieste.find(prova)).catch(async (e) => {
      console.error('Stato del service worker:', JSON.stringify(await stato()),
        'iscrizione:', JSON.stringify(esito));
      throw e;
    });

    // 3. App davanti: l'avviso arriva alla pagina (anche se l'app ascolta più tardi), e
    //    nessuna notifica di sistema.
    await page.bringToFront();
    await push({ title: 'Generale', body: 'Luca: stasera alle 21', route: '/chat/generale', data: { channel: 'generale' } });
    const ascolta = () => page.evaluate(() => {
      window.avvisi = [];
      milanacNotifiche.ascolta((...a) => window.avvisi.push(a));
    });
    await ascolta();
    const avviso = await aspetta('avviso alla pagina', () => page.evaluate(() => window.avvisi[0]));
    assert.deepStrictEqual(avviso,
      ['notifica', 'Generale', 'Luca: stasera alle 21', '/chat/generale', '{"channel":"generale"}']);
    assert.deepStrictEqual((await stato()).chieste, []);

    // 4. App chiusa (la scheda è su un'altra pagina del sito): notifica di sistema, con la
    //    sezione come etichetta (dieci messaggi dello stesso canale non ne fanno dieci).
    //    Senza finestra Chrome non sa nascondere una scheda: il caso "app aperta ma
    //    dietro" passa dallo stesso ramo.
    await page.goto(origine + '/altrove');
    await push({ title: 'Generale', body: 'Primo', route: '/chat/generale', data: { channel: 'generale' } });
    assert.deepStrictEqual(await chiesta('prima notifica di sistema', (x) => x.body === 'Primo'), {
      title: 'Generale', body: 'Primo', tag: '/chat/generale', data: { route: '/chat/generale' },
      icon: origine + '/app/icons/Icon-192.png', renotify: true,
    });
    await push({ title: 'Generale', body: 'Secondo', route: '/chat/generale', data: { channel: 'generale' } });
    assert.strictEqual(
      (await chiesta('seconda notifica dello stesso canale', (x) => x.body === 'Secondo')).tag,
      '/chat/generale');
    // Un indirizzo esterno come sezione non passa: si apre l'app.
    await push({ title: 'Strano', body: '', route: 'https://esempio.invalid/', data: {} });
    const strana = await chiesta('notifica con sezione non valida', (x) => x.title === 'Strano');
    assert.deepStrictEqual([strana.tag, strana.data], ['/', { route: '/' }]);
    // Un testo che non è JSON diventa una notifica con il nome del club, verso la Home.
    await cdp.send('ServiceWorker.deliverPushMessage', {
      origin: origine, registrationId: registrazione.registrationId, data: 'non è JSON',
    });
    const semplice = await chiesta('notifica da un testo non JSON', (x) => x.title === 'MILANAC Pro Club');
    assert.deepStrictEqual([semplice.body, semplice.data], ['', { route: '/' }]);
    const dopo = await stato();
    assert.strictEqual(dopo.chieste.length, 4, JSON.stringify(dopo));
    // Il sistema può non avere dove mostrarle (server di prova): non è un errore nostro.
    // Opzioni sbagliate invece sì.
    assert.deepStrictEqual(dopo.errori.filter((e) => e.startsWith('TypeError')), [], JSON.stringify(dopo));

    // 5. Clic sulla notifica con l'app aperta: la notifica si chiude e la sezione si apre
    //    lì. Con la notifica vera se il sistema la tiene, altrimenti con una di prova.
    await page.goto(origine + '/app/');
    await ascolta();
    const vera = await sw.evaluate(async () => {
      self.__chiuse = 0;
      const n = (await self.registration.getNotifications()).find((x) => x.tag === '/chat/generale');
      if (n) {
        self.dispatchEvent(new NotificationEvent('notificationclick', { notification: n }));
        return true;
      }
      const clic = new Event('notificationclick');
      Object.defineProperty(clic, 'notification', {
        value: { data: { route: '/chat/generale' }, close() { self.__chiuse++; } },
      });
      clic.waitUntil = () => {};
      self.dispatchEvent(clic);
      return false;
    });
    const clic = await aspetta('sezione aperta dal clic', () =>
      page.evaluate(() => window.avvisi.find((a) => a[0] === 'apri')));
    assert.deepStrictEqual(clic.slice(0, 4), ['apri', '', '', '/chat/generale']);
    if (vera) {
      assert.strictEqual((await stato()).sistema.some((n) => n.tag === '/chat/generale'), false);
    } else {
      assert.strictEqual(await sw.evaluate(() => self.__chiuse), 1);
    }

    // 6. Notifiche spente: l'iscrizione (se c'era) si toglie e resta lo stato del permesso.
    assert.strictEqual(await page.evaluate(() => milanacNotifiche.disattiva()), esito.endpoint);
    assert.strictEqual((await page.evaluate(() => milanacNotifiche.iscrizione())).endpoint, '');

    console.log('Notifiche nel browser: service worker e pagina OK' +
      (esito.errore ? ` (iscrizione vera non disponibile qui: ${esito.errore})` : '') +
      (vera ? '' : ` (il sistema non tiene le notifiche: ${dopo.errori[0] || 'nessun errore'})`));
  } finally {
    await browser.close();
    server.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
