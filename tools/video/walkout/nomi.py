"""IMMI → IMMU sulla maglia del portiere: cambia solo l'ultima lettera.

Il carattere della maglia è "minuscolo" (ımmı): la u è una n capovolta. In ogni
fotogramma la n si prende dalla prima m della stessa scritta (prima gamba e metà del primo
arco, metà del secondo arco e ultima gamba, così gli angoli sono quelli giusti), si
ruota di 180° e si mette al posto dell'ultima I, che si cancella. Carattere, bordino
chiaro, sfocatura e luce sono quindi quelli del video, fotogramma per fotogramma."""
import glob, os, sys
import cv2
import numpy as np

# Zona dove cercare la scritta, altezza delle lettere (px), bordino chiaro intorno alle
# lettere (px), soglia di "scuro" rispetto alla maglia intorno e se il bordino si ridisegna
# (nel primo piano è un filo bianco in basso a sinistra: girando la n finirebbe in alto).
JOBS = {
    'S2': dict(region=(300, 400, 800, 760), h=41, rim=3, dark=.62, redraw=True),
    'S17': dict(region=(470, 760, 720, 860), h=18, rim=2, dark=.72, redraw=True),
}


def letters(fr, cfg):
    """Le lettere della scritta: le due m e l'ultima I, ognuna con box (x, y, w, h) e
    maschera in coordinate del fotogramma. Le I sono i pezzi stretti ai due capi della
    riga; le m stanno in mezzo, divise dove le colonne scure sono meno (una m può uscire
    spezzata dalla soglia, quindi conta la zona e non il pezzo)."""
    x0, y0, x1, y1 = cfg['region']
    H = cfg['h']
    v = cv2.cvtColor(fr[y0:y1, x0:x1], cv2.COLOR_BGR2HSV)[..., 2].astype(np.float32)
    bg = cv2.GaussianBlur(v, (0, 0), 3 * H / 4)
    dark = (v < bg * cfg['dark']).astype(np.uint8)
    # Per la forma delle lettere una soglia più larga: nei fotogrammi mossi il grigio
    # delle lettere è più chiaro e la soglia stretta ne lascerebbe fuori metà.
    loose = (v < bg * .82).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(dark, 8)
    pieces = [dict(x=st[k][0], y=st[k][1], w=st[k][2], h=st[k][3], k=k)
              for k in range(1, n) if .55 * H <= st[k][3] <= 1.4 * H and st[k][2] <= 2.2 * H]
    if not pieces:
        return None
    # La riga della scritta: pezzi alla stessa altezza con la sequenza I, m, m (, I).
    thin = lambda q: q['w'] < .45 * q['h']
    is_m = lambda q: .8 * q['h'] < q['w'] < 1.7 * q['h']
    gap = lambda a, b: b['x'] - (a['x'] + a['w'])
    found = None
    for p in sorted(pieces, key=lambda q: q['y']):
        cy = p['y'] + p['h'] / 2
        row = sorted([q for q in pieces if abs(q['y'] + q['h'] / 2 - cy) < .35 * H],
                     key=lambda q: q['x'])
        for j in range(1, len(row) - 1):
            i1, a, b = row[j - 1], row[j], row[j + 1]
            if thin(i1) and is_m(a) and is_m(b) and 0 <= gap(i1, a) < .9 * H \
                    and -2 <= gap(a, b) < .6 * H:
                nxt = row[j + 2] if j + 2 < len(row) else None
                i2 = nxt if nxt is not None and thin(nxt) and 0 <= gap(b, nxt) < .9 * H else None
                found = (i1, [a, b], i2)
                break
        if found:
            break
    if found is None:
        return None
    i1, mids, i2 = found
    gap_guess = .2 * H
    row = [i1] + mids + ([i2] if i2 else [])
    top = min(q['y'] for q in row)
    bot = max(q['y'] + q['h'] for q in row)
    a, b = min(q['x'] for q in mids), max(q['x'] + q['w'] for q in mids)
    if b - a < 1.6 * H:
        return None
    gap = a - (i1['x'] + i1['w'])
    if i2 is None:
        # Ultima I troppo chiara per la soglia: dove deve stare, larga come la prima.
        i2 = dict(x=b + max(gap, gap_guess), y=i1['y'], w=i1['w'], h=i1['h'], k=None)
    # Divisione fra le due m: la colonna più vuota nel terzo centrale.
    band = dark[top:bot, a:b]
    prof = band.sum(0)
    c0, c1 = (b - a) // 3, 2 * (b - a) // 3
    split = a + c0 + int(np.argmin(prof[c0:c1]))

    def part(xa, xb):
        mask = np.zeros(fr.shape[:2], np.uint8)
        mask[y0 + top:y0 + bot, x0 + xa:x0 + xb] = loose[top:bot, xa:xb]
        ys, xs = np.where(dark[top:bot, xa:xb] > 0)
        return dict(x=x0 + xa + xs.min(), y=y0 + top + ys.min(), w=xs.max() - xs.min() + 1,
                    h=ys.max() - ys.min() + 1, full=mask)
    m1, m2 = part(a, split), part(split, b)
    if i2['k'] is None:
        full = np.zeros(fr.shape[:2], np.uint8)
        full[y0 + i2['y']:y0 + i2['y'] + i2['h'], x0 + i2['x']:x0 + i2['x'] + i2['w']] = 1
    else:
        # Tutta la colonna della I sull'altezza della riga: con la soglia il piede della
        # I a volte resta un puntino staccato.
        full = np.zeros(fr.shape[:2], np.uint8)
        xa, xb = max(i2['x'] - 1, 0), i2['x'] + i2['w'] + 1
        ya, yb = max(top - 2, 0), bot + 2
        full[y0 + ya:y0 + yb, x0 + xa:x0 + xb] = loose[ya:yb, xa:xb] | (lab[ya:yb, xa:xb] == i2['k'])
    # Spazio fra la prima I e la prima m: lo stesso fra la seconda m e la u.
    i2 = dict(x=x0 + i2['x'], y=y0 + i2['y'], w=i2['w'], h=i2['h'], full=full,
              gap=max(gap, 1), seen=i2['k'] is not None)
    return m1, m2, i2


def full_mask(c, shape):
    return c['full']


def stems(mask):
    """Centri delle tre gambe della m (colonne piene nella metà bassa)."""
    h = mask.shape[0]
    low = mask[h // 2:]
    prof = low.sum(0) / max(low.shape[0], 1)
    cols = prof > .55
    runs, start = [], None
    for i, on in enumerate(list(cols) + [False]):
        if on and start is None:
            start = i
        elif not on and start is not None:
            runs.append((start, i - 1))
            start = None
    if len(runs) != 3:
        return None
    return [(a + b) / 2 for a, b in runs]


def solid(mask, k):
    """La lettera piena: chiusi i buchi dove la soglia ha lasciato fuori qualche pixel
    più chiaro (riflessi), senza riempire lo spazio fra le gambe."""
    closed = cv2.morphologyEx(mask, cv2.MORPH_CLOSE,
                              cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))
    inv = (closed == 0).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(inv, 4)
    out = closed.copy()
    for i in range(1, n):
        if st[i][4] < 6 * k:
            out[lab == i] = 1
    return out


def make_u(fr, m1, rim, up, redraw):
    """La u (colore e trasparenza) costruita dalla prima m, ingrandita di [up]."""
    full = solid(full_mask(m1, fr.shape[:2]), 2 * rim - 1)
    x, y, w, h = m1['x'], m1['y'], m1['w'], m1['h']
    X0, Y0 = max(x - rim, 0), max(y - rim, 0)
    X1, Y1 = min(x + w + rim, fr.shape[1]), min(y + h + rim, fr.shape[0])
    color = cv2.resize(fr[Y0:Y1, X0:X1].astype(np.float32), None, fx=up, fy=up,
                       interpolation=cv2.INTER_CUBIC)
    # Trasparenza = quanto il pixel è scuro fra maglia e lettera: solo la lettera, con i
    # suoi bordi morbidi; il bordino chiaro resta fuori (si ridisegna dal lato giusto).
    v = cv2.cvtColor(fr[Y0:Y1, X0:X1], cv2.COLOR_BGR2HSV)[..., 2].astype(np.float32)
    sub = full[Y0:Y1, X0:X1]
    near = cv2.dilate(sub, np.ones((3, 3), np.uint8)) > 0
    ring = (cv2.dilate(sub, np.ones((2 * rim + 7,) * 2, np.uint8)) > 0) & ~(cv2.dilate(sub, np.ones((2 * rim + 3,) * 2, np.uint8)) > 0)
    bg_v = np.median(v[ring]) if ring.any() else v.max()
    # Il "pieno" della lettera si misura gamba per gamba (minimo locale): nei fotogrammi
    # mossi le tre gambe della m hanno scuri diversi, e la u non deve venire trasparente.
    k = max(3, 2 * rim + 3)
    let_v = cv2.erode(v, np.ones((k, k), np.uint8))
    alpha = np.clip((bg_v - v) / np.maximum(bg_v - let_v, 1), 0, 1) * near
    if not redraw:
        alpha = cv2.dilate(sub, np.ones((2 * rim + 1,) * 2, np.uint8)).astype(np.float32)
    alpha = cv2.resize(alpha, None, fx=up, fy=up, interpolation=cv2.INTER_LINEAR)
    sc = stems(full[y:y + h, x:x + w])
    if sc is None:
        return None
    # Metà di ciascun arco: dal centro fra prima e seconda gamba, e fra seconda e terza.
    a1 = int(round(((sc[0] + sc[1]) / 2 + x - X0) * up))
    a2 = int(round(((sc[1] + sc[2]) / 2 + x - X0) * up))
    # Gli archi possono stare a quote diverse di un soffio (scritta inclinata).
    letter = cv2.resize(full[Y0:Y1, X0:X1].astype(np.float32), None, fx=up, fy=up)

    def top(col):
        ys = np.where(letter[:, max(col, 0)] > .5)[0]
        return ys.min() if len(ys) else 0
    dy = top(a1 - 1) - top(a2)
    right_c = np.roll(color[:, a2:], dy, axis=0)
    right_a = np.roll(alpha[:, a2:], dy, axis=0)
    # Giunta di 2 colonne sfumate in cima all'arco.
    o = max(2, up)
    t = np.linspace(0, 1, o)[None, :, None]
    seam_c = color[:, a1 - o:a1] * (1 - t) + right_c[:, :o] * t
    seam_a = alpha[:, a1 - o:a1] * (1 - t[..., 0]) + right_a[:, :o] * t[..., 0]
    n_c = np.concatenate([color[:, :a1 - o], seam_c, right_c[:, o:]], axis=1)
    n_a = np.concatenate([alpha[:, :a1 - o], seam_a, right_a[:, o:]], axis=1)
    # Capovolta: la n diventa u.
    return n_c[::-1, ::-1], np.clip(n_a[::-1, ::-1], 0, 1)


def outline_style(fr, m1, m2, shift):
    """Colore del bordino chiaro e quanto si vede, misurati sulle due m di questo
    fotogramma nella stessa direzione in cui lo si disegna sulla u."""
    letter = solid(((m1['full'] | m2['full']) > 0).astype(np.uint8), 3)
    M = np.float32([[1, 0, shift[0]], [0, 1, shift[1]]])
    moved = cv2.warpAffine(letter, M, letter.shape[::-1], flags=cv2.INTER_NEAREST)
    edge = (moved > 0) & (cv2.dilate(letter, np.ones((3, 3), np.uint8)) == 0)
    if edge.sum() < 10:
        return None, 0
    hsv = cv2.cvtColor(fr, cv2.COLOR_BGR2HSV).astype(np.float32)
    v = hsv[..., 2]
    ys, xs = np.where(letter > 0)
    box = (slice(max(ys.min() - 12, 0), ys.max() + 12), slice(max(xs.min() - 12, 0), xs.max() + 12))
    around = np.zeros_like(letter, bool)
    around[box] = True
    around &= cv2.dilate(letter, np.ones((9, 9), np.uint8)) == 0
    bg_v = np.median(v[around])
    lit = edge & (v > bg_v * 1.04)
    if lit.sum() < 6:
        return None, 0
    color = np.median(fr[lit].astype(np.float32), axis=0)
    top = np.median(v[lit])
    lift = np.clip(np.mean(np.clip((v[edge] - bg_v) / max(top - bg_v, 1), 0, 1)) * 1.2, 0, 1)
    return color, lift


def fill_rows(img, mask, clean):
    """La maglia dove c'era la I, riga per riga: verso destra fino al colore subito dopo
    la I, verso sinistra quello della maglia pulita della stessa riga ([clean], presa più a
    destra: a sinistra c'è il bordo sfocato della m, e da sopra e sotto arriverebbero
    lettere e pieghe)."""
    out = img.astype(np.float32)
    for y in np.unique(np.where(mask > 0)[0]):
        xs = np.where(mask[y] > 0)[0]
        for r in np.split(xs, np.where(np.diff(xs) > 1)[0] + 1):
            b = min(r.max() + 1, img.shape[1] - 1)
            left = clean[y]
            t = (np.arange(r.min(), r.max() + 1) - r.min() + 1)[:, None] / (len(r) + 1)
            out[y, r.min():r.max() + 1] = left * (1 - t) + out[y, b] * t
    # Un filo di grana come la maglia intorno, senza righe nette.
    soft = cv2.GaussianBlur(out, (0, 0), 1.0)
    m = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), 1.0)[..., None]
    return np.clip(out * (1 - m) + soft * m, 0, 255).astype(np.uint8)


def fix(fr, cfg, offset=None):
    """[offset]: distanza fra la fine della seconda m e l'inizio della u (dove stava la
    I), già lisciata sui fotogrammi vicini perché la u non tremi."""
    found = letters(fr, cfg)
    if found is None:
        return fr, False
    m1, m2, i2 = found
    rim = cfg['rim']
    up = 4 if cfg['h'] < 25 else 2
    u = make_u(fr, m1, rim, up, cfg['redraw'])
    if u is None:
        return fr, False
    u_c, u_a = u
    # Via la vecchia I (con il suo bordino), ricostruendo la maglia intorno.
    i_mask = cv2.dilate(full_mask(i2, fr.shape[:2]), np.ones((2 * rim + 5, 2 * rim + 5), np.uint8))
    # Solo la I: non la m accanto (fino al suo bordo vero) e non la piega della maglia
    # sotto la scritta.
    m2_core = cv2.morphologyEx(full_mask(m2, fr.shape[:2]), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    i_mask &= (m2_core == 0).astype(np.uint8)
    i_mask[:max(i2['y'] - rim - 1, 0)] = 0
    i_mask[max(i2['y'] + i2['h'], m2['y'] + m2['h']) + rim + 2:] = 0
    # Maglia pulita riga per riga: subito a destra della I, lontano dalle lettere.
    xa = i2['x'] + i2['w'] + rim + 2
    xb = min(xa + int(1.2 * cfg['h']), fr.shape[1])
    strip = fr[:, xa:xb].astype(np.float32)
    lum = strip.mean(axis=2)
    clean = np.array([np.median(strip[y][lum[y] >= np.percentile(lum[y], 40)], axis=0)
                      if xb > xa else fr[y, xa].astype(np.float32) for y in range(fr.shape[0])])
    out = fill_rows(fr, i_mask, clean)
    # La u parte dove partiva la I ed è centrata in altezza sulla scritta.
    uh, uw = u_c.shape[0] / up, u_c.shape[1] / up
    lead = np.where(u_a.max(axis=0) > .5)[0]
    lead = (lead[0] / up) if len(lead) else rim
    cx0 = m2['x'] + m2['w'] + (i2['gap'] if offset is None else offset) - lead
    mid = ((m1['y'] + m1['h'] / 2) + (m2['y'] + m2['h'] / 2)) / 2
    cy0 = mid - uh / 2
    X0, Y0 = int(np.floor(cx0)) - 3, int(np.floor(cy0))
    X1, Y1 = int(np.ceil(cx0 + uw)) + 1, int(np.ceil(cy0 + uh)) + 4
    # Rimpicciolita alla misura vera e messa nella posizione esatta (anche a metà pixel).
    small = (int(round(uw)), int(round(uh)))
    s_c = cv2.resize(u_c, small, interpolation=cv2.INTER_AREA)
    s_a = cv2.resize(u_a, small, interpolation=cv2.INTER_AREA)
    M = np.float32([[1, 0, cx0 - X0], [0, 1, cy0 - Y0]])
    size = (X1 - X0, Y1 - Y0)
    col = cv2.warpAffine(s_c, M, size, flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    # Tono della lettera vicina (l'ultima gamba della seconda m), con la grana della m.
    near_m = full_mask(m2, fr.shape[:2]).copy()
    near_m[:, :m2['x'] + int(m2['w'] * .6)] = 0
    near_m = cv2.erode(near_m, np.ones((3, 3), np.uint8))
    if near_m.sum() > 8:
        tone = np.median(fr[near_m > 0].astype(np.float32), axis=0)
        col = tone + (col - cv2.GaussianBlur(col, (0, 0), 2)) * .8
    al = cv2.GaussianBlur(cv2.warpAffine(s_a, M, size, flags=cv2.INTER_LINEAR), (0, 0), .6)[..., None]
    region = out[Y0:Y1, X0:X1].astype(np.float32)
    # Bordino chiaro in basso a sinistra, come sulle altre lettere.
    s = cfg['h'] / 41 * 2
    shift = (-max(1, round(s)), max(1, round(s)))
    o_color, lift = outline_style(fr, m1, m2, shift)
    if cfg['redraw'] and o_color is not None and lift > .05:
        M2 = np.float32([[1, 0, shift[0]], [0, 1, shift[1]]])
        body = al[..., 0]
        moved = cv2.warpAffine(body, M2, body.shape[::-1], flags=cv2.INTER_LINEAR)
        ring = np.clip(moved - body, 0, 1)
        ring = cv2.GaussianBlur(ring, (0, 0), .5)[..., None] * lift
        region = region * (1 - ring) + o_color * ring
    out[Y0:Y1, X0:X1] = np.clip(region * (1 - al) + col * al, 0, 255).astype(np.uint8)
    return out, True


def run(name):
    cfg = JOBS[name]
    files = sorted(glob.glob(f'shots/{name}/*.png'))
    out_dir = f'out/n_{name}'
    os.makedirs(out_dir, exist_ok=True)
    missed = []
    # Dove stava la I rispetto alla seconda m, fotogramma per fotogramma, poi lisciato.
    offs = []
    for p in files:
        r = letters(cv2.imread(p), cfg)
        offs.append(np.nan if r is None else
                    (r[2]['x'] - (r[1]['x'] + r[1]['w']) if r[2]['seen'] else r[2]['gap']))
    offs = np.array(offs, float)
    offs[np.isnan(offs)] = np.nanmedian(offs)
    pad = np.pad(offs, 2, mode='edge')
    smooth = np.array([np.median(pad[i:i + 5]) for i in range(len(offs))])
    smooth = np.convolve(np.pad(smooth, 1, mode='edge'), np.ones(3) / 3, mode='valid')
    for i, p in enumerate(files):
        res, ok = fix(cv2.imread(p), cfg, smooth[i])
        if not ok:
            missed.append(os.path.basename(p))
        cv2.imwrite(f'{out_dir}/{i:04d}.png', res)
    print(name, len(files), 'fotogrammi', 'senza correzione:', missed or 'nessuno')


if __name__ == '__main__':
    for n in (sys.argv[1:] or JOBS):
        run(n)
