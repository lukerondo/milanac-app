"""Scrive gli slogan sugli striscioni vuoti del video (fotogrammi PNG di uno shot)."""
import glob, os, sys
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Permanent Marker (Apache 2.0): `npm pack @fontsource/permanent-marker` ed estrarre il .woff.
FONT = 'fonts/x/package/files/permanent-marker-latin-400-normal.woff'
RED = (28, 20, 176)     # BGR, rosso vernice
BLACK = (22, 20, 20)

# Angoli interni del telo (TL, TR, BR, BL) sul fotogramma di riferimento, bordo del telo
# (sotto il quale si sfocano i cartelloni) e righe degli slogan: (testo, colore).
BANNERS = {
    'S1': dict(quad=[(50, 700), (1030, 640), (1030, 1400), (50, 1410)], hem=1500,
               ref=10),
    'S3': dict(quad=[(45, 670), (960, 650), (960, 1420), (45, 1420)], hem=1515, ref=57),
    'S5': dict(quad=[(45, 480), (1035, 770), (1035, 1420), (45, 1395)], hem=1515,
               ref=106),
    'S7': dict(quad=[(45, 830), (1035, 470), (1035, 1490), (45, 1515)], hem=1600,
               ref=152),
}


def plate(lines, w=2000, h=1400):
    """Lo slogan su sfondo trasparente: righe centrate, la più lunga quasi a tutta
    larghezza, stessa altezza delle lettere su tutte le righe."""
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    size = 600
    while True:
        f = ImageFont.truetype(FONT, size)
        boxes = [d.textbbox((0, 0), t, font=f) for t, _ in lines]
        widest = max(b[2] - b[0] for b in boxes)
        line_h = max(b[3] - b[1] for b in boxes)
        total = line_h * len(lines) + line_h * .22 * (len(lines) - 1)
        if widest <= w * .92 and total <= h * .86:
            break
        size -= 8
    y = (h - total) / 2
    for (t, color), b in zip(lines, boxes):
        x = (w - (b[2] - b[0])) / 2 - b[0]
        # BGR -> RGB per PIL
        d.text((x, y - b[1]), t, font=f, fill=(color[2], color[1], color[0], 235))
        y += line_h * 1.22
    a = np.array(img)
    # Vernice: bordi un po' sbavati.
    a[..., 3] = cv2.GaussianBlur(a[..., 3], (0, 0), 1.6)
    return a


def track(frames, ref):
    """Spostamento di ogni fotogramma rispetto a quello di riferimento (camera quasi
    ferma): correlazione di fase sul quadro rimpicciolito."""
    g = lambda im: np.float32(cv2.cvtColor(cv2.resize(im, (540, 960)), cv2.COLOR_BGR2GRAY))
    base = g(frames[ref])
    win = cv2.createHanningWindow(base.shape[::-1], cv2.CV_32F)
    out = []
    for im in frames:
        (dx, dy), _ = cv2.phaseCorrelate(base, g(im), win)
        out.append((dx * 2, dy * 2))
    # Liscio, senza tremolii.
    arr = np.array(out)
    k = np.ones(5) / 5
    for c in range(2):
        arr[:, c] = np.convolve(np.pad(arr[:, c], 2, mode='edge'), k, mode='valid')
    return arr


def composite(frame, text_rgba, quad, shift, hem):
    h, w = frame.shape[:2]
    ph, pw = text_rgba.shape[:2]
    dst = np.float32(quad) + np.float32(shift)
    H = cv2.getPerspectiveTransform(np.float32([(0, 0), (pw, 0), (pw, ph), (0, ph)]), dst)
    warped = cv2.warpPerspective(text_rgba, H, (w, h), flags=cv2.INTER_LINEAR)
    # Le pieghe del telo spostano un po' la scritta.
    gray = np.float32(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
    hp = cv2.GaussianBlur(gray, (0, 0), 6) - cv2.GaussianBlur(gray, (0, 0), 40)
    gy, gx = np.mgrid[0:h, 0:w].astype(np.float32)
    warped = cv2.remap(warped, gx + hp * .05, gy + hp * .12, cv2.INTER_LINEAR)
    alpha = warped[..., 3:4].astype(np.float32) / 255 * .93
    color = warped[..., :3].astype(np.float32) / 255
    f = frame.astype(np.float32)
    # Multiply: luce e pieghe del telo passano sopra la vernice.
    out = f * (1 - alpha + alpha * color)
    # Cartelloni sotto lo striscione: scritte finte dell'AI, sfocate e scurite.
    y0 = int(hem + shift[1])
    if y0 < h:
        band = out[y0:].copy()
        blurred = cv2.GaussianBlur(band, (0, 0), 22) * .72
        ramp = np.clip((np.arange(h - y0) / 40.0), 0, 1)[:, None, None]
        out[y0:] = band * (1 - ramp) + blurred * ramp
    return np.clip(out, 0, 255).astype(np.uint8)


def run(shot, lines, out_dir, mirror=False):
    cfg = BANNERS[shot]
    files = sorted(glob.glob(f'shots/{shot}/*.png'))
    frames = [cv2.imread(p) for p in files]
    if mirror:
        frames = [cv2.flip(f, 1) for f in frames]
    quad = cfg['quad']
    if mirror:
        quad = [(1080 - x, y) for (x, y) in [quad[1], quad[0], quad[3], quad[2]]]
    shifts = track(frames, cfg['ref'] - int(os.path.basename(files[0])[:4]))
    text = plate(lines)
    text_bgra = text[..., [2, 1, 0, 3]]
    os.makedirs(out_dir, exist_ok=True)
    for i, (fr, s) in enumerate(zip(frames, shifts)):
        cv2.imwrite(f'{out_dir}/{i:04d}.png', composite(fr, text_bgra, quad, s, cfg['hem']))
    print(out_dir, len(frames), 'deriva max', np.abs(shifts).max(axis=0).round(1))


if __name__ == '__main__':
    R, K = RED, BLACK
    jobs = {
        'b1_immu': ('S1', [('FORZA', K), ('IMMU!', R)], False),
        'b2_fabio': ('S3', [('FABIO', R), ('UNICO', K), ('CAPITANO', K)], False),
        'b3_chrys': ('S5', [('CHRYS', R), ('IL MOTORE', K)], False),
        'b4_martin': ('S7', [('MARTIN', R), ('UNO DI NOI', K)], False),
        'b5_zio': ('S1', [('ZIO', R), ('FOR', K), ('PRESIDENT', K)], True),
        'b6_vicio': ('S3', [('VICIO', R), ('NUMBER', K), ('ONE', K)], True),
    }
    for name in (sys.argv[1:] or jobs):
        shot, lines, mirror = jobs[name]
        run(shot, lines, f'out/{name}', mirror)
