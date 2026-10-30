"""Corregge i nomi sulle maglie: trova le lettere sbagliate sul fotogramma di riferimento,
le segue sugli altri (scala e spostamento), le cancella e scrive quelle giuste con colore,
luce e sfocatura dell'originale."""
import glob, os, sys
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

APP = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'assets', 'fonts')
BARLOW = f'{APP}/Barlow-700.ttf'
OSWALD = f'{APP}/Oswald-500.ttf'

# Zone approssimative (sul fotogramma di riferimento) dove cercare le lettere sbagliate,
# testo giusto e carattere; "track" è la zona della schiena da seguire.
JOBS = {
    'S2': dict(ref=33, track=(410, 560, 660, 1010), shirt='giallo',
               words=[((430, 590, 630, 672), 'IMMU', BARLOW)]),
    'S17': dict(ref=441, track=(500, 760, 680, 1000), shirt='giallo',
                words=[((530, 785, 630, 832), 'IMMU', BARLOW)]),
    'S8': dict(ref=176, track=(470, 410, 690, 700), shirt='righe',
               words=[((478, 425, 672, 494), 'MARTIN', BARLOW),
                      ((498, 492, 652, 690), '4', OSWALD)]),
    'S9': dict(ref=199, track=(500, 450, 740, 720), shirt='righe',
               words=[((492, 465, 716, 526), 'ZIO', BARLOW)]),
}


def detail(im):
    g = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY).astype(np.float32)
    d = g - cv2.GaussianBlur(g, (0, 0), 9)
    return cv2.normalize(d, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)


def track(frames, ref, box):
    """(scala, x, y) dell'angolo della zona seguita, fotogramma per fotogramma, sui
    dettagli dell'immagine (non sulla luce, che nel tunnel cambia molto)."""
    x0, y0, x1, y1 = box
    tpl = detail(frames[ref])[y0:y1, x0:x1]
    out = {ref: (1.0, float(x0), float(y0))}
    for step in (1, -1):
        s, x, y = out[ref]
        i = ref + step
        while 0 <= i < len(frames):
            g = detail(frames[i])
            best = (-2, s, x, y)
            for ds in (-.02, -.01, 0, .01, .02):
                sc = float(np.clip(s + ds, .85, 1.15))
                t = cv2.resize(tpl, None, fx=sc, fy=sc, interpolation=cv2.INTER_AREA)
                th, tw = t.shape
                m = 60
                ax, ay = int(max(0, x - m)), int(max(0, y - m))
                bx, by = int(min(g.shape[1], x + tw + m)), int(min(g.shape[0], y + th + m))
                win = g[ay:by, ax:bx]
                if win.shape[0] < th or win.shape[1] < tw:
                    continue
                r = cv2.matchTemplate(win, t, cv2.TM_CCOEFF_NORMED)
                _, mv, _, loc = cv2.minMaxLoc(r)
                if mv > best[0]:
                    best = (mv, sc, ax + loc[0], ay + loc[1])
            _, s, x, y = best
            out[i] = (s, float(x), float(y))
            i += step
    return out


def letters(img, rough, shirt):
    """Maschera delle lettere nella zona [rough] del fotogramma di riferimento."""
    x0, y0, x1, y1 = rough
    hsv = cv2.cvtColor(img[y0:y1, x0:x1], cv2.COLOR_BGR2HSV)
    sat, v = hsv[..., 1].astype(int), hsv[..., 2].astype(int)
    if shirt == 'giallo':
        m = v < 150
    else:
        m = (sat < 85) & (v > 85)
    m = m.astype(np.uint8)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(m, 8)
    keep = np.zeros_like(m)
    for k in range(1, n):
        if stats[k, cv2.CC_STAT_AREA] >= 12:
            keep[lab == k] = 1
    full = np.zeros(img.shape[:2], np.uint8)
    full[y0:y1, x0:x1] = keep
    ys, xs = np.where(full > 0)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    # Il bordino chiaro delle lettere nere (maglia gialla) va via con loro.
    grow = 5 if shirt == 'giallo' else 3
    full = cv2.dilate(full, np.ones((2 * grow + 1, 2 * grow + 1), np.uint8))
    return full, box


def detect_here(fr, words, s, x, y, ref_xy, shirt):
    out = np.zeros(fr.shape[:2], np.uint8)
    for (bx0, by0, bx1, by1), _, _ in words:
        wx0, wy0, wx1, wy1 = warp((bx0, by0, bx1, by1), s, x, y, ref_xy)
        X0, X1 = int(max(wx0 - 24, 0)), int(min(wx1 + 24, fr.shape[1]))
        Y0, Y1 = int(max(wy0 - 5, 0)), int(min(wy1 + 5, fr.shape[0]))
        hsv = cv2.cvtColor(fr[Y0:Y1, X0:X1], cv2.COLOR_BGR2HSV)
        sat, v = hsv[..., 1].astype(np.float32), hsv[..., 2].astype(np.float32)
        if shirt == 'giallo':
            m = v < 150
        else:
            # Tratti chiari rispetto alle righe intorno (il bagliore è uniforme, sparisce).
            m = ((v - cv2.GaussianBlur(v, (0, 0), 7)) > 16) & (sat < 110)
        m = m.astype(np.uint8)
        n, lab, st, _ = cv2.connectedComponentsWithStats(m, 8)
        keep = np.zeros_like(m)
        for k in range(1, n):
            if st[k, cv2.CC_STAT_AREA] >= 10:
                keep[lab == k] = 1
        grow = 5 if shirt == 'giallo' else 3
        keep = cv2.dilate(keep, np.ones((2 * grow + 1, 2 * grow + 1), np.uint8))
        out[Y0:Y1, X0:X1] |= keep
    return out


def warp(points_or_mask, s, x, y, ref_xy, shape=None):
    M = np.float32([[s, 0, x - ref_xy[0] * s], [0, s, y - ref_xy[1] * s]])
    if shape is not None:
        return cv2.warpAffine(points_or_mask, M, (shape[1], shape[0]), flags=cv2.INTER_NEAREST)
    bx0, by0, bx1, by1 = points_or_mask
    return (bx0 * s + M[0, 2], by0 * s + M[1, 2], bx1 * s + M[0, 2], by1 * s + M[1, 2])


def fill_columns(img, mask):
    """Righe verticali: ogni colonna della zona si ricostruisce dai colori sopra e sotto."""
    out = img.astype(np.float32)
    ys_all, xs_all = np.where(mask > 0)
    for x in np.unique(xs_all):
        ys = np.where(mask[:, x] > 0)[0]
        # Tratti separati (nome e numero) si riempiono uno alla volta.
        runs = np.split(ys, np.where(np.diff(ys) > 1)[0] + 1)
        for r in runs:
            top, bot = r.min(), r.max()
            a = out[max(top - 2, 0), x].copy()
            b = out[min(bot + 2, out.shape[0] - 1), x].copy()
            t = (np.arange(top, bot + 1) - top + 1)[:, None] / (bot - top + 2)
            out[top:bot + 1, x] = a * (1 - t) + b * t
    return out


def render(text, font_path, cap_h, color, outline):
    """La scritta (BGRA) con le maiuscole alte [cap_h] pixel."""
    big = 4
    f = ImageFont.truetype(font_path, 200)
    d = ImageDraw.Draw(Image.new('RGBA', (10, 10)))
    bb = d.textbbox((0, 0), 'H' if not text.isdigit() else text, font=f)
    size = int(200 * cap_h * big / (bb[3] - bb[1]))
    f = ImageFont.truetype(font_path, size)
    sw = int(round(outline[1] * big)) if outline else 0
    bb = d.textbbox((0, 0), text, font=f, stroke_width=sw)
    w, h = bb[2] - bb[0] + 4, bb[3] - bb[1] + 4
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((2 - bb[0], 2 - bb[1]), text, font=f,
                             fill=tuple(int(c) for c in color[::-1]) + (255,), stroke_width=sw,
                             stroke_fill=(tuple(outline[0][::-1]) + (255,)) if outline else None)
    img = img.resize((max(1, w // big), max(1, h // big)), Image.LANCZOS)
    return np.array(img)[..., [2, 1, 0, 3]].astype(np.float32)


def run(name):
    cfg = JOBS[name]
    files = sorted(glob.glob(f'shots/{name}/*.png'))
    first = int(os.path.basename(files[0])[:4])
    frames = [cv2.imread(p) for p in files]
    ref = cfg['ref'] - first
    tr = track(frames, ref, cfg['track'])
    ref_xy = cfg['track'][:2]
    shirt = cfg['shirt']
    # Lettere sbagliate sul fotogramma di riferimento: maschera unica e box di ogni scritta.
    union = np.zeros(frames[ref].shape[:2], np.uint8)
    words = []
    for rough, text, font in cfg['words']:
        m, box = letters(frames[ref], rough, shirt)
        union |= m
        words.append((box, text, font))
    out_dir = f'out/n_{name}'
    os.makedirs(out_dir, exist_ok=True)
    for i, fr in enumerate(frames):
        s, x, y = tr[i]
        mask = warp(union, s, x, y, ref_xy, fr.shape)
        # In più le lettere vecchie trovate in questo fotogramma, vicino a dove dovrebbero
        # essere: se il tracciamento sbaglia di qualche pixel non resta nessun avanzo.
        mask |= detect_here(fr, words, s, x, y, ref_xy, shirt)
        mask = cv2.dilate(mask, np.ones((3, 3), np.uint8))
        ys, xs = np.where(mask > 0)
        pad = 14
        lo, hi = xs.min(), xs.max()
        # Un nome più lungo del vecchio (MARTIN al posto di CHRYS) deve starci tutto.
        for (bx0, by0, bx1, by1), text, font in words:
            wx0, wy0, wx1, wy1 = warp((bx0, by0, bx1, by1), s, x, y, ref_xy)
            ww = render(text, font, (wy1 - wy0), (255, 255, 255), None).shape[1]
            c = (wx0 + wx1) / 2
            lo, hi = min(lo, int(c - ww / 2) - 6), max(hi, int(c + ww / 2) + 6)
        X0, Y0 = max(lo - pad, 0), max(ys.min() - pad, 0)
        X1, Y1 = min(hi + pad, fr.shape[1]), min(ys.max() + pad, fr.shape[0])
        patch = fr[Y0:Y1, X0:X1].astype(np.float32)
        pm = mask[Y0:Y1, X0:X1]
        # Colore delle lettere originali in questo fotogramma (luce e tinta).
        hsv = cv2.cvtColor(fr[Y0:Y1, X0:X1], cv2.COLOR_BGR2HSV)
        core = cv2.erode(pm, np.ones((7, 7), np.uint8)) > 0
        if shirt == 'giallo':
            clean = cv2.inpaint(fr[Y0:Y1, X0:X1], pm * 255, 9, cv2.INPAINT_TELEA).astype(np.float32)
        else:
            clean = cv2.GaussianBlur(fill_columns(patch, pm), (0, 0), .7)
        lum = cv2.GaussianBlur(cv2.cvtColor(clean.astype(np.uint8), cv2.COLOR_BGR2GRAY).astype(np.float32), (0, 0), 4)
        comp = clean.copy()
        for (bx0, by0, bx1, by1), text, font in words:
            wx0, wy0, wx1, wy1 = warp((bx0, by0, bx1, by1), s, x, y, ref_xy)
            sel = core & (np.zeros_like(core))
            region = np.zeros_like(core)
            region[int(wy0 - Y0):int(wy1 - Y0), int(wx0 - X0):int(wx1 - X0)] = True
            sel = core & region
            if shirt == 'giallo':
                color = np.array([30, 30, 32])
            else:
                vals = fr[Y0:Y1, X0:X1][sel]
                vals = vals[cv2.cvtColor(vals[None], cv2.COLOR_BGR2HSV)[0][:, 2] > 100] if len(vals) else vals
                color = np.median(vals, axis=0) if len(vals) > 15 else np.array([225, 225, 225])
            outline = ((225, 232, 232), .9 * s) if shirt == 'giallo' else None
            word = render(text, font, (wy1 - wy0), color, outline)
            word[..., 3] = cv2.GaussianBlur(word[..., 3], (0, 0), .6 * s)
            # Centrata dove stava la vecchia scritta.
            cx, cy = (wx0 + wx1) / 2 - X0, (wy0 + wy1) / 2 - Y0
            ox, oy = int(round(cx - word.shape[1] / 2)), int(round(cy - word.shape[0] / 2))
            H, W = comp.shape[:2]
            xs0, ys0 = max(ox, 0), max(oy, 0)
            xe, ye = min(ox + word.shape[1], W), min(oy + word.shape[0], H)
            if xe <= xs0 or ye <= ys0:
                continue
            wpart = word[ys0 - oy:ye - oy, xs0 - ox:xe - ox]
            a = wpart[..., 3:4] / 255
            shade = np.clip((lum[ys0:ye, xs0:xe] / max(np.median(lum), 1)) ** .35, .75, 1.2)[..., None]
            comp[ys0:ye, xs0:xe] = comp[ys0:ye, xs0:xe] * (1 - a) + wpart[..., :3] * shade * a
        # Bordo morbido: fuori dalla zona ritoccata resta l'originale.
        zone = cv2.dilate(pm, np.ones((9, 9), np.uint8)).astype(np.float32)
        zone = np.maximum(zone, 0)
        for (bx0, by0, bx1, by1), text, font in words:
            wx0, wy0, wx1, wy1 = warp((bx0, by0, bx1, by1), s, x, y, ref_xy)
            grow = (wx1 - wx0) * .45
            zone[max(int(wy0 - Y0) - 4, 0):int(wy1 - Y0) + 4, max(int(wx0 - X0 - grow), 0):int(wx1 - X0 + grow)] = 1
        zone = cv2.GaussianBlur(zone, (0, 0), 2.5)[..., None]
        res = fr.copy()
        res[Y0:Y1, X0:X1] = np.clip(patch * (1 - zone) + comp * zone, 0, 255).astype(np.uint8)
        cv2.imwrite(f'{out_dir}/{i:04d}.png', res)
    print(name, len(frames), 'scala', round(min(t[0] for t in tr.values()), 3), round(max(t[0] for t in tr.values()), 3),
          'box', [w[0] for w in words])


if __name__ == '__main__':
    for n in (sys.argv[1:] or JOBS):
        run(n)
