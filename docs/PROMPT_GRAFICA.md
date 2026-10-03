# MILANAC Pro Club – Prompt per la grafica

I prompt sono in inglese perché i generatori video/immagini (Veo, Sora, Kling, Runway, Midjourney…)
rendono meglio così. **Non chiedere testi o loghi nel video/immagine**: scritte, stemma e barra di
caricamento li sovrappone l'app (restano nitidi e modificabili).

---

## 1. Video Intro (10–15 secondi, verticale 9:16)

### Versione A – Text-to-video (senza foto dei giocatori)

```
Cinematic vertical 9:16 intro video, 12 seconds, for an esports football club called a "Pro Club".
Night, inside a huge Italian football stadium inspired by San Siro: steep stands, red and black
choreography flags waving, red flares and smoke, golden sparks floating in the air.

Shot list:
0–3s: slow aerial descent from the stadium roof through red smoke, the pitch below lit by floodlights.
3–8s: eleven footballers in black and red vertical-striped kits with no logos and no sponsors walk
out of the tunnel side by side in slow motion, confident, determined faces, captain in the center,
light rain catching the floodlights, dramatic rim lighting.
8–11s: low-angle hero shot, the players stop in a line facing the camera, the camera slowly
pushes in, golden light particles swirl around them.
11–12s: the image gently darkens and blurs toward the center, leaving an empty dark area in the
middle and a clean dark band at the bottom of the frame (space for a crest and a loading bar).

Style: premium sports broadcast, video-game cinematic, high contrast, deep blacks, red (#C8102E)
and gold (#D4AF37) color grading, anamorphic lens flares, shallow depth of field, 24fps.
No text, no letters, no logos, no watermarks, no real brands, no real people.
```

### Versione B – Image-to-video (con screenshot/avatar dei vostri giocatori di FC 27)
Carica come immagine iniziale uno screenshot della squadra (es. foto di gruppo in FC 27) e usa:

```
Animate this image into a 12-second vertical 9:16 cinematic intro. Keep the players' faces,
kits and builds exactly as in the image. The camera slowly pushes in from a low angle while the
players come to life: subtle breathing, a confident look toward the camera, the captain clenches
his fist. Stadium floodlights flicker, red smoke and golden sparks drift across the frame, red and
black flags wave in the stands behind. In the last 2 seconds the scene gently darkens toward the
center and the bottom, leaving clean dark space for a crest and a loading bar.
Color grade: deep black, red #C8102E, gold #D4AF37. No text, no logos, no watermarks.
```

### Consigli tecnici per il file
- Formato **MP4 (H.264)**, 1080×1920, 24–30 fps, **max ~8 MB**, audio facoltativo (l'app parte senza audio,
  che si può attivare con un tasto)
- L'ultimo secondo deve essere scuro e "fermo": l'app sfuma da lì alla Home senza stacchi.
- Generane 3–4 varianti e scegli la migliore; se lo strumento fa clip da 5–8s, unisci 2 clip.

---

## 2. Albo d'oro – sfondo "giocatore che ammira la bacheca"

L'app usa **un'immagine di sfondo** + i **trofei veri caricati dal Direttivo** posizionati sulle mensole.
Per questo le mensole nell'immagine devono essere **vuote**.

```
Vertical 9:16 digital illustration, semi-realistic video-game style. A luxurious club trophy room
at night: a tall dark wood and glass display cabinet with four EMPTY illuminated glass shelves,
warm golden spotlights from above each shelf, soft reflections on a black marble floor, red velvet
wall behind, subtle red and black striped banners on the sides.
In the foreground, seen from behind and slightly to the side, a football player in a black and red
vertical-striped kit with no logos stands looking up at the cabinet with admiration, one hand
resting on his hip, the light from the cabinet outlining his silhouette (rim light).
The player occupies the lower-left third of the image; the cabinet with the empty shelves occupies
the center and top, fully visible and front-facing, shelves perfectly horizontal.
Mood: proud, legendary, cinematic. Palette: black, deep red #C8102E, gold #D4AF37.
No trophies, no text, no logos, no watermarks.
```

Per l'effetto 2.5D (parallasse) chiedi anche, con lo stesso prompt, **due livelli separati**:
- solo la sala con la bacheca vuota (senza giocatore)
- solo il giocatore su **sfondo trasparente** (PNG)

### Trofei (per il Direttivo)
Per ogni trofeo serve una **PNG con sfondo trasparente**, frontale, ~1000px. Prompt di esempio:
```
A single golden football trophy cup with red enamel details, front view, centered,
studio lighting, photorealistic, isolated on a transparent background, no text.
```
(o fotografie dei trofei reali con lo sfondo rimosso, es. con remove.bg)

---

## 3. Nuovo stemma (facoltativo)

```
Esports football club crest, shield shape, modern vector style, flat with subtle gold bevel.
Red and black vertical stripes, a stylized red devil head with small horns integrated with a
game controller silhouette, gold outline, a small star on top.
Leave a clean horizontal band for the club name (it will be added later in vector).
Centered on a transparent background, high contrast, readable at small sizes,
no text, no existing club logos.
```
Poi il nome **MILANAC PRO CLUB** si aggiunge in vettoriale (SVG), così lo stemma resta nitido come icona dell'app.
