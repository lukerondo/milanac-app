#!/usr/bin/env node
// Disegna le cornici delle carte e l'omino (immagini originali, generate da qui) e le
// salva in PNG; tools/carte/genera.sh le converte in WebP dentro assets/carte/.
//
// Per ogni materiale: il fondo (metallo spazzolato, archi in rilievo, luce dietro il
// giocatore) e la targa bassa che taglia la figura. Bordi, scritte e numeri li disegna
// l'app (lib/features/carta): qui c'è solo la materia.
//
// Uso: node tools/carte/genera.js <cartella di uscita>   (serve Playwright con Chromium)
const { chromium } = require('playwright');
const path = require('path');

// Disegno in 300×430; l'app lo stende su 210×300.
const W = 300, H = 430;
// Fascia della targa: da qui in giù (in unità del disegno).
const PLATE_TOP = 250;
// Pixel per unità: la carta grande sul telefono è larga circa 900 px.
const SCALE = 2.6;

const SKINS = {
  vuota:     { g: ['#8A8A93', '#5F5F68', '#3E3E45', '#55555D', '#27272C'], inner: '#B4B4BC', plate: '#000000', glow: '#FFFFFF', glowAlpha: .3, dark: true },
  bronzo:    { g: ['#F6D3AE', '#D29660', '#9A5E33', '#C4854F', '#70421F'], inner: '#FBE2C6', plate: '#3A1E08', glow: '#FFE9D2' },
  argento:   { g: ['#FFFFFF', '#D9DFE4', '#9FA9B1', '#CDD4D9', '#7C8790'], inner: '#FFFFFF', plate: '#20272C', glow: '#FFFFFF' },
  oro:       { g: ['#FFF3BF', '#EBCB6C', '#C19A33', '#E2C063', '#9B7724'], inner: '#FFF6CF', plate: '#3D2D08', glow: '#FFF7D6' },
  rossonera: { g: ['#E01E36', '#A00F22', '#4A0810', '#16090B', '#0B0B0C'], inner: '#8C6F2A', plate: '#000000', glow: '#FF5A6E', stripes: true, dark: true },
  nero_oro:  { g: ['#34302A', '#19181A', '#0A0A0B', '#151416', '#050505'], inner: '#8C6F2A', plate: '#000000', glow: '#F1D382', facets: true, dark: true },
  blu:       { g: ['#3B74FF', '#1747C8', '#0A2A80', '#0C2F92', '#050F33'], inner: '#6FCBFF', plate: '#020926', glow: '#8FD6FF', facets: true, dark: true },
};

const stops = t => t.g.map((c, i) => `<stop offset="${(i / (t.g.length - 1)).toFixed(2)}" stop-color="${c}"/>`).join('');
const PLATE = 'M0 266 C90 255 210 255 300 266 L300 430 L0 430 Z';
const defs = t => `
  <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="${W}" y2="${H}">${stops(t)}</linearGradient>
  <filter id="brush" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".012 .9" numOctaves="2" seed="7" result="n"/><feColorMatrix in="n" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  .9 .4 0 0 -.42"/></filter>`;

// Il fondo: tutto il rettangolo (la forma della carta la ritaglia l'app).
function fondo(t) {
  const facets = t.facets ? `<g opacity=".5" fill="${t.inner}" fill-opacity=".1" stroke="${t.inner}" stroke-opacity=".5" stroke-width=".8"><path d="M0 80 L96 8 L62 150 Z"/><path d="M190 0 L300 34 L268 150 Z"/><path d="M232 232 L300 196 L300 318 Z"/><path d="M0 268 L58 204 L36 344 Z"/></g>` : '';
  const stripes = t.stripes ? `<g opacity=".42" mask="url(#sm)">${Array.from({ length: 12 }, (_, i) => `<rect x="${6 + i * 25}" y="0" width="12.5" height="300" fill="#000"/>`).join('')}</g>` : '';
  const arcs = '<circle cx="330" cy="-40" r="250"/><circle cx="352" cy="-56" r="318"/><path d="M-20 262 C70 250 170 232 320 150"/><path d="M-20 276 C80 262 180 246 320 170"/>';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}"><defs>${defs(t)}
    <radialGradient id="stage" cx=".64" cy=".3" r=".52"><stop offset="0" stop-color="${t.glow}" stop-opacity="${t.glowAlpha || .62}"/><stop offset=".55" stop-color="${t.glow}" stop-opacity=".12"/><stop offset="1" stop-color="${t.glow}" stop-opacity="0"/></radialGradient>
    <linearGradient id="spec" x1="0" y1=".1" x2="1" y2=".7"><stop offset=".3" stop-color="#fff" stop-opacity="0"/><stop offset=".43" stop-color="#fff" stop-opacity=".3"/><stop offset=".5" stop-color="#fff" stop-opacity=".06"/><stop offset=".56" stop-color="#fff" stop-opacity="0"/></linearGradient>
    <linearGradient id="smg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff"/><stop offset=".6" stop-color="#fff" stop-opacity=".6"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
    <mask id="sm"><rect width="300" height="300" fill="url(#smg)"/></mask></defs>
    <rect width="${W}" height="${H}" fill="url(#g)"/>
    ${stripes}
    <rect width="${W}" height="${H}" filter="url(#brush)" opacity="${t.dark ? '.16' : '.5'}" style="mix-blend-mode:overlay"/>
    <g fill="none" stroke-linecap="round">
      <g stroke="#fff" stroke-opacity="${t.dark ? '.3' : '.5'}" stroke-width="1.6">${arcs}</g>
      <g stroke="#000" stroke-opacity=".28" stroke-width="1.6" transform="translate(1.6 2)">${arcs}</g>
    </g>
    ${facets}
    <rect width="${W}" height="${H}" fill="url(#stage)"/>
    <rect width="${W}" height="${H}" fill="url(#spec)"/>
  </svg>`;
}

// La targa bassa (nome e numeri): trasparente sopra il suo bordo curvo.
function targa(t) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 ${PLATE_TOP} ${W} ${H - PLATE_TOP}" width="${W}" height="${H - PLATE_TOP}"><defs>${defs(t)}
    <linearGradient id="plate" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${t.plate}" stop-opacity="0"/><stop offset=".12" stop-color="${t.plate}" stop-opacity=".2"/><stop offset="1" stop-color="${t.plate}" stop-opacity=".42"/></linearGradient>
    <clipPath id="pc"><path d="${PLATE}"/></clipPath></defs>
    <path d="${PLATE}" fill="url(#g)"/>
    <g clip-path="url(#pc)"><rect y="240" width="${W}" height="190" filter="url(#brush)" opacity="${t.dark ? '.12' : '.4'}" style="mix-blend-mode:overlay"/></g>
    <path d="${PLATE}" fill="url(#plate)"/>
    <path d="M0 266 C90 255 210 255 300 266" fill="none" stroke="#fff" stroke-opacity="${t.dark ? '.45' : '.7'}" stroke-width="1.5"/>
    <path d="M0 268.6 C90 257.6 210 257.6 300 268.6" fill="none" stroke="#000" stroke-opacity=".4" stroke-width="1.2"/>
    <path d="M0 274 C90 263 210 263 300 274" fill="none" stroke="${t.inner}" stroke-opacity=".45" stroke-width=".8"/>
  </svg>`;
}

// L'omino: busto senza volto, grigio neutro, con la maglia rossonera a bande strette.
// È la figura di chi non ha ancora caricato la foto (carte, avatar). Disegnato in 200×200.
function omino() {
  const [s1, s2, s3] = ['#C6CDD9', '#98A1B4', '#7F889C'], [h1, h2] = ['#3B4152', '#1D212B'];
  const head = 'M100 18 C124 18 140 36 140 62 C140 75 138 86 134 96 C129 111 118 125 100 127 C82 125 71 111 66 96 C62 86 60 75 60 62 C60 36 76 18 100 18 Z';
  const hair = 'M58 74 C54 58 55 45 60 35 C57 31 57 26 60 21 C63 24 66 24 68 21 C70 15 75 11 81 9 C82 13 85 14 88 12 C92 6 99 3 107 4 C107 8 110 10 114 8 C121 6 127 9 132 15 C131 18 133 20 137 20 C142 25 144 31 144 37 C142 36 141 38 141 41 C146 51 146 63 142 74 C140 62 136 52 129 46 C119 41 108 46 96 42 C84 39 73 43 68 51 C63 57 60 65 58 74 Z';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" width="200" height="200"><defs>
    <linearGradient id="sk" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${s1}"/><stop offset="1" stop-color="${s2}"/></linearGradient>
    <linearGradient id="nk" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${s3}"/><stop offset="1" stop-color="${s2}"/></linearGradient>
    <linearGradient id="hr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${h1}"/><stop offset="1" stop-color="${h2}"/></linearGradient>
    <pattern id="st" width="13" height="13" patternUnits="userSpaceOnUse" x="3.5"><rect width="6.5" height="13" fill="#C61C23"/><rect x="6.5" width="6.5" height="13" fill="#121214"/></pattern>
    <linearGradient id="sh" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".5"/></linearGradient>
    <radialGradient id="li" cx=".5" cy="0" r=".8"><stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
    <linearGradient id="fs" x1="0" y1="0" x2="1" y2="0"><stop offset=".45" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".2"/></linearGradient>
    <linearGradient id="ft" x1="0" y1="0" x2="0" y2="1"><stop offset=".35" stop-color="#000" stop-opacity=".2"/><stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient>
    <clipPath id="hc"><path d="${head}"/></clipPath>
    <clipPath id="tc"><path d="M6 200 C8 170 24 153 58 145 L82 137 C90 152 110 152 118 137 L142 145 C176 153 192 170 194 200 Z"/></clipPath></defs>
    <path d="M81 106 L81 140 C88 153 112 153 119 140 L119 106 Z" fill="url(#nk)"/>
    <path d="M81 112 C90 126 110 126 119 112 L119 124 C110 134 90 134 81 124 Z" fill="#000" opacity=".22"/>
    <g clip-path="url(#tc)">
      <rect x="0" y="130" width="200" height="72" fill="url(#st)"/>
      <rect x="0" y="130" width="200" height="72" fill="url(#sh)"/>
      <rect x="0" y="130" width="200" height="72" fill="url(#li)"/>
      <path d="M58 145 C50 160 46 180 46 200 L6 200 C8 170 24 153 58 145 Z M142 145 C150 160 154 180 154 200 L194 200 C192 170 176 153 142 145 Z" fill="#000" opacity=".3"/>
      <path d="M58 146 C50 162 46 182 46 200 M142 146 C150 162 154 182 154 200" fill="none" stroke="#D6B354" stroke-width="1.2" opacity=".7"/>
    </g>
    <path d="M76 134 C88 156 112 156 124 134 L129 140 C115 166 85 166 71 140 Z" fill="#0E0E10"/>
    <path d="M73.5 137.5 C87 161 113 161 126.5 137.5" fill="none" stroke="#D6B354" stroke-width="1.4"/>
    <path d="M61 66 C52 61 49 76 53 86 C55 93 62 93 63 88 Z M139 66 C148 61 151 76 147 86 C145 93 138 93 137 88 Z" fill="${s2}"/>
    <path d="${head}" fill="url(#sk)"/>
    <g clip-path="url(#hc)"><rect x="56" y="14" width="88" height="116" fill="url(#fs)"/><rect x="56" y="14" width="88" height="60" fill="url(#ft)"/></g>
    <path d="${hair}" fill="url(#hr)"/>
  </svg>`;
}

(async () => {
  const out = process.argv[2];
  if (!out) throw new Error('Uso: node tools/carte/genera.js <cartella di uscita>');
  const browser = await chromium.launch();
  const shot = async (name, svg, w, h, scale) => {
    const page = await browser.newPage({ viewport: { width: Math.ceil(w), height: Math.ceil(h) }, deviceScaleFactor: scale });
    await page.setContent(`<style>html,body{margin:0;background:transparent}svg{display:block}</style>${svg}`);
    await page.screenshot({ path: path.join(out, name + '.png'), omitBackground: true, clip: { x: 0, y: 0, width: w, height: h } });
    await page.close();
  };
  for (const [name, t] of Object.entries(SKINS)) {
    await shot(`${name}_fondo`, fondo(t), W, H, SCALE);
    await shot(`${name}_targa`, targa(t), W, H - PLATE_TOP, SCALE);
  }
  await shot('omino', omino(), 200, 200, 3);
  await browser.close();
  console.log(`Disegnate ${Object.keys(SKINS).length} cornici e l'omino in ${out}`);
})();
