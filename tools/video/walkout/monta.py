"""Monta il video: walkout (striscione → giocatore, sei volte), poi azione, gol, esultanza
e fumo. Scrive i fotogrammi in un master video (senza audio) e la mappa dei tempi per
l'audio (segmenti dell'originale con la loro velocità)."""
import glob, json, subprocess
import cv2
import numpy as np

SRC = 'in/video.mp4'
W, H = 1080, 1920
FPS = 24


def pngs(folder, take=None, skip=0):
    files = sorted(glob.glob(f'{folder}/*.png'))[skip:]
    return [('png', f) for f in (files[:take] if take else files)]


def orig(a, b, speed=1.0):
    """Fotogrammi originali da a a b compresi, accelerati di [speed] (si saltano)."""
    n = int(round((b - a + 1) / speed))
    return [('src', int(round(x))) for x in np.linspace(a, b, n)]


walkout = []
plan = [
    (pngs('out/b1_immu', 20, 1), pngs('out/n_S2', 20, 2)),
    (pngs('out/b2_fabio', 20, 2), orig(72, 91)),
    (pngs('out/b3_chrys', 20, 1), orig(120, 139)),
    (pngs('out/b4_martin', 20, 2), pngs('out/n_S8', 20, 1)),
    (pngs('out/b5_zio', 20, 1), pngs('out/n_S9', 20, 1)),
    (pngs('out/b6_vicio', 20, 2), orig(211, 233)),
]
flash_at = []  # (indice, intensità)
for banner, player in plan:
    if walkout:
        flash_at += [(len(walkout) - 1, .6), (len(walkout), .35)]
    walkout += banner + player
action = (orig(234, 259) + orig(260, 288, 1.6) + orig(289, 359, 1.25) + orig(360, 431)
          + pngs('out/n_S17') + orig(451, 490))
timeline = walkout + action

# Audio: walkout con l'audio originale continuo, poi l'azione con le stesse velocità.
audio = [dict(src=0.0, dur=len(walkout) / FPS, speed=1.0)]
for a, b, sp in [(234, 259, 1.0), (260, 288, 1.6), (289, 359, 1.25), (360, 490, 1.0)]:
    audio.append(dict(src=a / FPS, dur=(b - a + 1) / FPS, speed=sp))
json.dump(dict(frames=len(timeline), audio=audio,
               goal=(len(walkout) + 26 + 18 + 57 + (366 - 360)) / FPS), open('out/timeline.json', 'w'))

dec = subprocess.Popen(['ffmpeg', '-v', 'error', '-i', SRC, '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-'],
                       stdout=subprocess.PIPE)
enc = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'bgr24',
                        '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-', '-c:v', 'libx264', '-crf', '12',
                        '-preset', 'medium', '-pix_fmt', 'yuv420p', 'out/master.mp4'], stdin=subprocess.PIPE)
cur, frame = -1, None


def src(n):
    global cur, frame
    while cur < n:
        buf = dec.stdout.read(W * H * 3)
        frame = np.frombuffer(buf, np.uint8).reshape(H, W, 3)
        cur += 1
    return frame


flashes = dict(flash_at)
total = len(timeline)
for i, (kind, ref) in enumerate(timeline):
    im = cv2.imread(ref) if kind == 'png' else src(ref).copy()
    if i in flashes:
        im = cv2.addWeighted(im, 1 - flashes[i], np.full_like(im, 255), flashes[i], 0)
    # Fine: il fumo sfuma nel nero (l'app passa da qui alla Home).
    tail = total - i
    if tail <= 18:
        im = (im.astype(np.float32) * (tail - 1) / 18).astype(np.uint8)
    enc.stdin.write(im.tobytes())
enc.stdin.close(); enc.wait(); dec.kill()
print('fotogrammi', total, 'durata', round(total / FPS, 3), 's', 'gol a', json.load(open('out/timeline.json'))['goal'])
