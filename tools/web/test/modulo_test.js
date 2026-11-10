// Prova nel browser vero del modulo di candidatura di sito/index.html, con FormSubmit simulato
// (nessuna candidatura parte davvero): invio riuscito, nuovo tentativo dopo un errore, errore che
// resta (messaggio, "Riprova", email già scritta al club, campi ancora compilati), modulo non
// attivato e rete assente.
//
//   node tools/web/test/modulo_test.js
//
// Usa Playwright (playwright-core va bene) e Chrome: CHROME_CHANNEL=chrome per quello installato.
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

const SITO = path.join(__dirname, '..', '..', '..', 'sito');

function sito() {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const file = path.join(SITO, url.pathname === '/' ? 'index.html' : url.pathname);
    if (!file.startsWith(SITO) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404);
      return res.end();
    }
    res.writeHead(200, { 'Content-Type': file.endsWith('.html') ? 'text/html' : 'application/octet-stream' });
    res.end(fs.readFileSync(file));
  });
  return new Promise((ok) => server.listen(0, '127.0.0.1', () => ok(server)));
}

async function aspetta(cosa, leggi, ms = 15000) {
  const fine = Date.now() + ms;
  for (;;) {
    const v = await leggi();
    if (v) return v;
    if (Date.now() > fine) throw new Error('Non è successo in tempo: ' + cosa);
    await new Promise((ok) => setTimeout(ok, 50));
  }
}

// Compila il modulo come farebbe un candidato e lo invia.
async function compilaEInvia(page) {
  // Il modulo sta nel pannello che si apre con "Candidati".
  await page.evaluate(() => document.querySelector('a[data-open-form]').click());
  await page.waitForSelector('#c-nome', { state: 'visible' });
  return page.evaluate(() => {
    const f = document.getElementById('candidatura');
    const set = (sel, v) => { f.querySelector(sel).value = v; };
    set('#c-nome', 'Mario Prova');
    set('#c-anno', '2000');
    f.querySelector('input[name=Piattaforma][value=PC]').checked = true;
    set('#c-ea', 'MarioEA');
    const ruolo = f.querySelector('#c-ruolo');
    ruolo.value = Array.from(ruolo.options).find((o) => o.value).value;
    set('#c-esperienza', 'Tre stagioni da centrocampista.');
    set('#c-email', 'mario@example.com');
    ['#c-milan', '#c-sere', '#c-privacy'].forEach((s) => { f.querySelector(s).checked = true; });
    f.requestSubmit();
  });
}

(async () => {
  const server = await sito();
  const origine = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({
    channel: process.env.CHROME_CHANNEL || undefined,
    executablePath: process.env.CHROME_EXECUTABLE || undefined,
    args: ['--no-sandbox'],
  });
  try {
    // Ogni caso: le risposte che FormSubmit darà, in ordine. 'rete' = connessione caduta.
    async function caso(risposte) {
      const context = await browser.newContext();
      const page = await context.newPage();
      const errori = [];
      page.on('pageerror', (e) => errori.push(e.message));
      const richieste = [];
      // Fuori dal sito locale niente rete (font, animazioni): la pagina deve funzionare lo stesso.
      await context.route((url) => !url.href.startsWith(origine), async (route) => {
        const url = route.request().url();
        if (!url.startsWith('https://formsubmit.co/')) return route.abort();
        richieste.push({ url, metodo: route.request().method(), corpo: route.request().postData() || '' });
        const r = risposte.shift();
        if (r === 'rete' || !r) return route.abort('connectionreset');
        return route.fulfill({ status: r.status, contentType: 'application/json', body: JSON.stringify(r.json) });
      });
      await page.goto(origine + '/');
      // Prima dell'invio il ringraziamento non si vede (lo stile non deve scavalcare hidden).
      assert.strictEqual(await page.evaluate(() =>
        getComputedStyle(document.getElementById('grazie-box')).display), 'none');
      await compilaEInvia(page);
      return { context, page, richieste, errori };
    }
    const stato = (page) => page.evaluate(() => ({
      grazie: !document.getElementById('grazie-box').hidden &&
        getComputedStyle(document.getElementById('grazie-box')).display !== 'none',
      grazieVisibile: getComputedStyle(document.getElementById('grazie-box')).display !== 'none',
      modulo: !document.getElementById('candidatura').hidden,
      nota: document.getElementById('nota').hidden ? '' : document.getElementById('nota').textContent,
      errore: document.getElementById('nota').classList.contains('err'),
      bottone: document.querySelector('#candidatura button[type=submit]').textContent.trim(),
      occupato: document.querySelector('#candidatura button[type=submit]').disabled,
      mail: (document.querySelector('#nota a[href^="mailto:"]') || {}).href || '',
      nome: document.getElementById('c-nome').value,
    }));
    const OK = { status: 200, json: { success: 'true', message: 'The form was submitted successfully.' } };
    const ERRORE = { status: 500, json: { success: 'false', message: 'Server Error' } };

    // 1. Invio riuscito: una richiesta all'endpoint JSON, con le piattaforme in un campo solo.
    let c = await caso([OK]);
    let s = await aspetta('ringraziamento', async () => { const x = await stato(c.page); return x.grazie && x; });
    assert.strictEqual(s.modulo, false);
    assert.strictEqual(c.richieste.length, 1);
    assert.strictEqual(c.richieste[0].url, 'https://formsubmit.co/ajax/milanacproclub@proton.me');
    assert.strictEqual(c.richieste[0].metodo, 'POST');
    assert.match(c.richieste[0].corpo, /name="Piattaforme"\r\n\r\nPC\r\n/);
    assert.doesNotMatch(c.richieste[0].corpo, /name="Piattaforma"\r\n/);
    assert.deepStrictEqual(c.errori, []);
    await c.context.close();

    // 2. Errore del server, poi tutto bene: il secondo tentativo parte da solo.
    c = await caso([ERRORE, OK]);
    s = await aspetta('invio in corso', async () => { const x = await stato(c.page); return x.occupato && x; });
    assert.strictEqual(s.bottone, 'Invio in corso…');
    s = await aspetta('ringraziamento dopo il secondo tentativo', async () => { const x = await stato(c.page); return x.grazie && x; });
    assert.strictEqual(c.richieste.length, 2);
    await c.context.close();

    // 3. Errore che resta: messaggio, "Riprova", email già scritta, campi compilati. Poi "Riprova".
    c = await caso([ERRORE, ERRORE, OK]);
    s = await aspetta('messaggio di errore', async () => { const x = await stato(c.page); return x.errore && x; });
    assert.match(s.nota, /non risponde in questo momento/);
    assert.strictEqual(s.grazieVisibile, false);
    assert.match(s.nota, /Riprova/);
    assert.strictEqual(s.nome, 'Mario Prova');
    assert.strictEqual(s.occupato, false);
    assert.match(s.mail, /^mailto:milanacproclub@proton\.me\?subject=/);
    const corpo = decodeURIComponent(s.mail.split('&body=')[1]);
    assert.match(corpo, /Nome: Mario Prova/);
    assert.match(corpo, /EA ID: MarioEA/);
    assert.match(corpo, /Piattaforme: PC/);
    assert.doesNotMatch(corpo, /_subject|_honey|_captcha/);
    await c.page.click('#nota button');
    await aspetta('ringraziamento dopo "Riprova"', async () => (await stato(c.page)).grazie);
    assert.strictEqual(c.richieste.length, 3);
    await c.context.close();

    // 4. Modulo non ancora attivato su FormSubmit: lo dice, senza riprovare da solo.
    c = await caso([{ status: 200, json: { success: 'false', message: "This form needs Activation. We've sent you an email containing an 'Activate Form' button." } }]);
    s = await aspetta('messaggio di attivazione', async () => { const x = await stato(c.page); return x.errore && x; });
    assert.match(s.nota, /non è ancora attivo/);
    assert.strictEqual(c.richieste.length, 1);
    await c.context.close();

    // 5. Rete assente due volte: messaggio di errore e un tentativo in più.
    c = await caso(['rete', 'rete']);
    s = await aspetta('messaggio senza rete', async () => { const x = await stato(c.page); return x.errore && x; });
    assert.match(s.nota, /non risponde/);
    assert.strictEqual(c.richieste.length, 2);
    await c.context.close();

    console.log('Modulo di candidatura: invio, nuovi tentativi ed errori OK');
  } finally {
    await browser.close();
    server.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
