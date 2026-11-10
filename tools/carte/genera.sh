#!/usr/bin/env bash
# Rigenera assets/carte/ (cornici delle carte e omino) da tools/carte/genera.js.
# Servono Node con Playwright (Chromium) e Python con Pillow.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
node "$root/tools/carte/genera.js" "$tmp"
python3 - "$tmp" "$root/assets/carte" <<'PY'
import sys
from pathlib import Path
from PIL import Image

src, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
total = 0
for png in sorted(src.glob("*.png")):
    image = Image.open(png)
    target = out / f"{png.stem}.webp"
    if png.stem.endswith("_fondo"):
        # Il fondo è pieno: senza trasparenza pesa meno.
        image.convert("RGB").save(target, "WEBP", quality=80, method=6)
    else:
        image.save(target, "WEBP", quality=86, alpha_quality=92, method=6)
    total += target.stat().st_size
    print(f"{target.name}: {image.size[0]}x{image.size[1]}, {target.stat().st_size // 1024} KB")
print(f"Totale: {total // 1024} KB")
PY
