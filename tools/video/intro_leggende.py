"""Intro "Lampi di leggende" (assets/video/intro.mp4): le foto vere delle leggende montate
con ffmpeg, 15 secondi in verticale 720x1280 senza audio.

Uso: python3 tools/video/intro_leggende.py CARTELLA_FOTO [USCITA.mp4]
Nella cartella le foto con i nomi di SHOTS (pirlo.jpg, seedorf.jpg...). Le foto non stanno
nel repository. Per aggiungere una leggenda: una riga in SHOTS (le durate vanno ritoccate
per restare a 15 secondi: INTRO + somma delle durate - XF per ogni passaggio).
Servono ffmpeg e ImageMagick (convert).
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FOTO = sys.argv[1]
DEST = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "assets/video/intro.mp4")
OUT = tempfile.mkdtemp(prefix="intro_leggende_")
FONT = os.path.join(ROOT, "assets/fonts/Oswald-600.ttf")
FONT_B = os.path.join(ROOT, "assets/fonts/Barlow-600.ttf")
FPS, W, H = 24, 720, 1280
GOLD = "0xE8C96A"
CRF, GRAIN = "26", "5"

# (foto, nome, durata in secondi, centro x/y della spinta in avanti, inquadratura:
# "cover" riempie lo schermo, "wide" per le foto larghe su sfondo sfocato; per "cover"
# anche il punto da tenere quando la foto si taglia, da 0 a 1 in orizzontale e verticale)
SHOTS = [
    ("maldini.jpg", "MALDINI", 1.75, .5, .3, "cover", .5, .4),
    ("pirlo.jpg", "PIRLO", 1.75, .45, .25, "cover", .5, .5),
    ("seedorf.jpg", "SEEDORF", 1.75, .55, .15, "cover", .5, .5),
    ("shevchenko.jpg", "SHEVCHENKO", 1.75, .45, .2, "cover", .38, .5),
    ("kaka.jpg", "KAKÁ", 1.75, .5, .2, "cover", .68, .5),
    ("pato.jpg", "PATO", 1.75, .5, .15, "cover", .5, .5),
    ("ronaldinho.jpg", "RONALDINHO", 1.75, .5, .2, "cover", .5, .5),
    ("ibrahimovic.jpg", "IBRAHIMOVIĆ", 3.55, .5, .4, "wide", .5, .5),
]
INTRO = 1.6
XF = 0.3

def run(args):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args])
    if r.returncode:
        sys.exit(r.returncode)

def esc(s):
    return s.replace(":", r"\:").replace("'", r"\'")

def name_text(name, start):
    # Il nome in oro sopra lo stemma dell'app (che sta nel 25% in basso), con una riga sottile.
    a = f"if(lt(t,{start}),0,if(lt(t,{start}+.35),(t-{start})/.35,1))"
    return (
        f"drawbox=x=(iw-120)/2:y=0.615*ih:w=120:h=3:color={GOLD}@0.9:t=fill:"
        f"enable='gte(t,{start})',"
        f"drawtext=fontfile={FONT}:text='{esc(name)}':fontsize=78:fontcolor={GOLD}:"
        f"x=(w-text_w)/2:y=0.63*h:alpha='{a}':shadowcolor=black@0.8:shadowx=0:shadowy=4,"
        f"drawtext=fontfile={FONT_B}:text='LEGGENDA ROSSONERA':fontsize=26:fontcolor=white@0.85:"
        f"x=(w-text_w)/2:y=0.63*h+96:alpha='{a}'"
    )

def segment(i, f, name, dur, cx, cy, mode, fx, fy):
    n = int(round(dur * FPS))
    W2, H2 = W * 2, H * 2
    z = f"(1+0.09*n/{n})"  # spinta lenta in avanti
    crop = (f"crop=w='{W2}/{z}':h='{H2}/{z}':x='({W2}-{W2}/{z})*{cx}':y='({H2}-{H2}/{z})*{cy}',"
            f"scale={W}:{H}:flags=lanczos")
    if mode == "cover":
        graph = (f"[0:v]scale={W2}:{H2}:force_original_aspect_ratio=increase:flags=lanczos,"
                 f"crop={W2}:{H2}:(iw-{W2})*{fx}:(ih-{H2})*{fy},unsharp=7:7:0.8,"
                 f"setsar=1,format=yuv420p,"
                 f"setpts=N/{FPS}/TB,{crop}[v]")
    else:
        # Foto larga: sfondo sfocato e scuro, la foto intera in alto.
        graph = (f"[0:v]split[a][b];"
                 f"[a]scale={W2}:{H2}:force_original_aspect_ratio=increase,crop={W2}:{H2},"
                 f"gblur=sigma=40,eq=brightness=-0.18:saturation=0.7[bg];"
                 f"[b]scale={int(W2*1.08)}:-2:flags=lanczos,crop={W2}:ih[fg];"
                 f"[bg][fg]overlay=0:{int(H2*0.2)},setsar=1,format=yuv420p,"
                 f"setpts=N/{FPS}/TB,{crop}[v]")
    # Fascia scura morbida sotto i nomi, poi i nomi.
    graph += f";[v][1:v]overlay=0:0[vb];[vb]{name_text(name, 0.2)},fps={FPS}[o]"
    run(["-loop", "1", "-i", f"{FOTO}/{f}", "-loop", "1", "-i", band, "-filter_complex", graph, "-map", "[o]",
         "-frames:v", str(n), "-c:v", "libx264", "-crf", "8", "-preset", "veryfast",
         "-pix_fmt", "yuv420p", f"{OUT}/s{i}.mp4"])

def intro():
    n = int(round(INTRO * FPS))
    # Tre flash da fotografi sul nero, poi il titolo.
    flash = "+".join(f"exp(-pow((T-{t})*28,2))" for t in (0.1, 0.28, 0.46))
    a = "if(lt(t,.5),0,if(lt(t,.8),(t-.5)/.3,1))"
    graph = (f"color=c=black:s={W}x{H}:r={FPS}:d={INTRO},format=yuv420p,"
             f"drawtext=fontfile={FONT}:text='LAMPI DI LEGGENDE':fontsize=64:fontcolor={GOLD}:"
             f"x=(w-text_w)/2:y=0.42*h:alpha='{a}',"
             f"drawtext=fontfile={FONT_B}:text='MILANAC PRO CLUB':fontsize=26:fontcolor=white@0.8:"
             f"x=(w-text_w)/2:y=0.42*h+86:alpha='{a}',"
             f"geq=lum='clip(lum(X,Y)+255*({flash}),0,255)':cb='cb(X,Y)':cr='cr(X,Y)'")
    run(["-f", "lavfi", "-i", graph, "-frames:v", str(n), "-c:v", "libx264", "-crf", "8",
         "-preset", "veryfast", "-pix_fmt", "yuv420p", f"{OUT}/s0.mp4"])

band = f"{OUT}/band.png"
subprocess.run(["convert", "-size", f"{W}x{H}", "xc:none", "(", "-size", f"{W}x{int(H*.13)}",
                "gradient:none-black", ")", "-geometry", f"+0+{int(H*.5)}", "-composite",
                "(", "-size", f"{W}x{int(H*.5)}", "xc:black", ")", "-geometry", f"+0+{int(H*.63)}",
                "-composite", "-channel", "A", "-evaluate", "multiply", "0.55", "+channel", band],
               check=True)

intro()
for i, s in enumerate(SHOTS, 1):
    segment(i, *s)

# Catena di lampi bianchi tra i segmenti, colore, vignettatura, grana, nero finale.
durs = [INTRO] + [s[2] for s in SHOTS]
inputs, chain, last, offset = [], "", "[0:v]", 0.0
for i in range(len(durs)):
    inputs += ["-i", f"{OUT}/s{i}.mp4"]

for i in range(1, len(durs)):
    offset += durs[i - 1] - XF
    chain += f"{last}[{i}:v]xfade=transition=fadewhite:duration={XF}:offset={offset:.3f}[x{i}];"
    last = f"[x{i}]"
total = sum(durs) - XF * (len(durs) - 1)
chain += (f"{last}eq=contrast=1.12:saturation=0.92:gamma=0.97,vignette=PI/4.5,"
          f"noise=alls={GRAIN}:allf=t,fade=t=out:st={total-0.8:.2f}:d=0.8,format=yuv420p[o]")
run([*inputs, "-filter_complex", chain, "-map", "[o]", "-r", str(FPS), "-c:v", "libx264",
     "-crf", CRF, "-preset", "slow", "-profile:v", "high", "-pix_fmt", "yuv420p",
     "-movflags", "+faststart", "-an", DEST])
print(f"{DEST}: {total:.2f} s, {os.path.getsize(DEST) / 1e6:.2f} MB")
