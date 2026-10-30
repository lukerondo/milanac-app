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

---

## 4. Walkout della squadra (intro attuale, Seedance 2.5 su Leonardo, ottobre 2026)

Text to Video, 20 s, 9:16, audio attivo, con tre immagini di riferimento in quest'ordine: lo
stemma ritagliato, il foglio della divisa (fronte/retro) e le sei maglie negli armadietti (i
nomi giusti da copiare). Gli striscioni restano **vuoti**: le scritte, i nomi sbagliati
dall'AI sulle maglie e il montaggio si fanno dopo con `tools/video/walkout/`.

```
Vertical 9:16, 20 seconds, 18 shots joined by hard cuts. Cinematic walkout cutscene from a next-gen console football video game: glossy 3D game render, invented faces, not live-action, no real people, broadcast TV cameras, night, white floodlights. For the whole video: no music; no captions, lower thirds, player-name graphics, HUD, scoreboard, subtitles or watermark; every banner stays completely blank; the only lettering is the names and numbers printed on the shirt backs.

@Image1 is the club crest: copy the shield exactly (shape, colours, red devil, gold border), never mirrored, no background, as a small embroidered badge on the wearer's left chest and on some fan flags. @Image2 is the home kit, front and back. @Image3 shows the six shirt backs: copy names, numbers, colours and lettering exactly.

HOME KIT, identical in every shot: narrow vertical black and red stripes, crest @Image1 on the left chest, black shorts, black socks, large white name and number on the back, no sponsor, no brand logos. Captain FABIO 10, striker, wears a gold armband with a black C on his left arm. Also ZIO 5 centre-back, MARTIN 4 left-back, CHRYS 8 and VICIO 11 central midfielders, and five teammates.
GOALKEEPER IMMU 1: neon yellow goalkeeper shirt, shorts and socks with black details, black gloves, crest @Image1 on the left chest, large black name and number on the back.
Opponents, only from 10s: plain all-white kit, goalkeeper included.

STADIUM: huge packed Italian stadium at night, steep tiers, cylindrical ramp towers at the corners, red steel roof trusses; the curva behind the goal full of ultras, red flares, red smoke, red and black flags, some with crest @Image1.

BANNER SHOT: locked-off tripod camera, frontal, deep focus, all sharp. One long cream cotton banner, three times wider than tall, thin red hem, lower edge tied flat to the front railing, ends lashed to upright wooden poles held by fans behind it; nothing in front, cloth taut and still. It fills 85% of the frame width, centred, evenly lit. Ultras behind with raised scarves, red smoke above.

Shot 1 [0-1s]: banner shot, left of the curva; banner completely blank, no writing.
Shot 2 [1-2s]: dressing room; camera follows goalkeeper IMMU 1 (neon yellow, gloves) out through the door, name and number sharp.
Shot 3 [2-3s]: banner shot, centre of the curva; banner completely blank, no writing.
Shot 4 [3-4s]: concrete corridor; Steadicam behind FABIO 10, armband, name and number sharp.
Shot 5 [4-5s]: banner shot, right of the curva; banner completely blank, no writing.
Shot 6 [5-6s]: tunnel, cold white LED strips; camera behind CHRYS 8, name and number sharp.
Shot 7 [6-7s]: banner shot, upper tier; banner completely blank, no writing.
Shot 8 [7-8s]: tunnel; low camera behind MARTIN 4, name and number sharp, studs on concrete.
Shot 9 [8-9s]: tunnel mouth; camera behind ZIO 5 walking into floodlight glare, name and number sharp.
Shot 10 [9-10s]: camera behind VICIO 11 stepping onto the grass, name and number sharp, the roaring stadium opening up ahead.
Shot 11 [10-12s]: high broadcast camera behind the home goal, looking up the pitch: IMMU 1 catches the ball at his chest and at once rolls it out along the grass to ZIO 5, who passes first time to CHRYS 8. One white ball, always on the grass; white opponents a few metres away.
Shot 12 [12-13s]: pitch-level side tracking shot in midfield: CHRYS 8 passes first time to VICIO 11, who slides a first-time pass into the left channel. Every touch with the inside of the foot.
Shot 13 [13-14s]: MARTIN 4 overlaps on the left wing and rolls a first-time low cross across the box.
Shot 14 [14-15s]: low camera behind FABIO 10: first-time low shot with the inside of his right foot toward the bottom corner; the white goalkeeper dives.
Shot 15 [15-16s]: locked camera beside the post: the ball crosses the line, the net bulges.
Shot 16 [16-18s]: low camera behind FABIO 10, name and number sharp, as he runs to the curva and knee-slides, arms wide, then taps the crest on his chest; VICIO 11 and CHRYS 8 run in beside him; red flares blaze in the curva ahead.
Shot 17 [18-19s]: far end of the pitch: IMMU 1 seen from behind on his goal line, both fists raised to the sky, name and number sharp.
Shot 18 [19-20s]: camera perfectly still on the curva; red smoke drifts across and the image settles into calm, dark smoke, almost black.

AUDIO, live stadium sound only: [0-9s] wordless ultras chant and drums, studs clacking on concrete, growing louder; [9-10s] roar swells as they step onto the grass; [10-15s] crowd hum, the thud of the goalkeeper's catch, crisp ball contacts; [15-16s] huge goal roar; [16-19s] roar, hissing flares; [19-20s] fading to a low rumble. No music. No commentary, no voice-over, no dialogue.
```

