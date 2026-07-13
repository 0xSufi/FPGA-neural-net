#!/usr/bin/env python3
"""
Host sender for the Tang Primer 25K OCR demo.

Turns a number 0..99 (rendered, or segmented from a black-on-white image) into
per-digit 28x28 binarized tiles and streams them to the FPGA:

    frame = 0xA5 , ndigits(1|2) , ndigits * 784 pixel bytes (tens digit first)

The FPGA classifies each digit, shows the result on the PMOD_DTx2 display, and
echoes the recognised value back as ASCII ("NN\\r\\n"), which we print.

Examples
  python3 send_number.py --port /dev/ttyUSB1 --render 42
  python3 send_number.py --port /dev/ttyUSB1 --image scan.png
  python3 send_number.py --render 7 --dry          # no board: preview only
"""
import argparse, sys, glob
import numpy as np
from PIL import Image, ImageDraw, ImageFont

SYNC = 0xA5

# --------------------------------------------------------------------------
def _font(size):
    for p in sorted(glob.glob("/usr/share/fonts/truetype/**/*.ttf", recursive=True)):
        low = p.lower()
        if "sans" in low and "math" not in low:
            try: return ImageFont.truetype(p, size)
            except Exception: pass
    return ImageFont.load_default()

def render_tile(digit, size=22):
    """Render one printed digit centered in a 28x28, binarized to {0,1}. Ink=1."""
    img = Image.new("L", (28, 28), 0)
    d   = ImageDraw.Draw(img)
    f   = _font(size)
    s   = str(digit)
    try:
        bb = d.textbbox((0, 0), s, font=f); tw, th = bb[2]-bb[0], bb[3]-bb[1]
        ox, oy = -bb[0], -bb[1]
    except Exception:
        tw, th, ox, oy = 12, 18, 0, 0
    d.text(((28-tw)//2+ox, (28-th)//2+oy), s, fill=255, font=f)
    return (np.asarray(img, np.float32)/255.0 > 0.5).astype(np.uint8).reshape(-1)

def tile_from_box(mask):
    """Crop the ink bounding box, center it in 28x28 (~22px tall), binarize."""
    ys, xs = np.where(mask > 0)
    if len(xs) == 0:
        return np.zeros(28*28, np.uint8)
    y0, y1, x0, x1 = ys.min(), ys.max()+1, xs.min(), xs.max()+1
    crop = Image.fromarray((mask[y0:y1, x0:x1]*255).astype(np.uint8))
    h = 22; w = max(1, round(crop.width * 22 / crop.height))
    w = min(w, 24)
    crop = crop.resize((w, h), Image.BILINEAR)
    out = Image.new("L", (28, 28), 0)
    out.paste(crop, ((28-w)//2, (28-h)//2))
    return (np.asarray(out, np.float32)/255.0 > 0.5).astype(np.uint8).reshape(-1)

def image_to_tiles(path):
    """Segment a black-on-white number image into up to 2 digit tiles."""
    g = np.asarray(Image.open(path).convert("L"), np.float32)/255.0
    ink = (g < 0.5).astype(np.uint8)                 # dark ink -> 1
    cols = ink.sum(axis=0) > 0
    # group contiguous ink columns into digit blobs
    blobs, s = [], None
    for i, c in enumerate(cols):
        if c and s is None: s = i
        elif not c and s is not None: blobs.append((s, i)); s = None
    if s is not None: blobs.append((s, len(cols)))
    blobs = [b for b in blobs if b[1]-b[0] >= 2]     # drop noise
    if len(blobs) > 2:                               # keep the two widest
        blobs = sorted(blobs, key=lambda b: b[1]-b[0])[-2:]
    blobs = sorted(blobs, key=lambda b: b[0])        # left-to-right
    return [tile_from_box(ink[:, x0:x1]) for x0, x1 in blobs] or [np.zeros(28*28, np.uint8)]

# --------------------------------------------------------------------------
def preview(tiles):
    for t in tiles:
        a = t.reshape(28, 28)
        print("\n".join("".join("#" if v else "." for v in row) for row in a))
        print("-"*28)

def build_frame(tiles):
    f = bytearray([SYNC, len(tiles)])
    for t in tiles:
        f += bytes(int(v) & 1 for v in t)            # 784 bytes, 0/1
    return bytes(f)

def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--render", type=int, help="render this number 0..99 and send")
    g.add_argument("--image", type=str, help="black-on-white image of a number")
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--dry", action="store_true", help="don't open serial; preview only")
    a = ap.parse_args()

    if a.render is not None:
        n = a.render
        if not 0 <= n <= 99: sys.exit("number must be 0..99")
        tiles = [render_tile(n//10), render_tile(n%10)] if n >= 10 else [render_tile(n)]
    else:
        tiles = image_to_tiles(a.image)

    frame = build_frame(tiles)
    print(f"[host] {len(tiles)} digit(s), frame = {len(frame)} bytes")
    preview(tiles)
    if a.dry:
        print("[host] --dry: not sending"); return

    import time, serial                              # pip install pyserial
    with serial.Serial(a.port, a.baud, timeout=3) as ser:
        ser.reset_input_buffer()
        ser.write(frame); ser.flush()
        time.sleep(0.3)                              # let the FPGA finish inferring + echoing
        line = ser.readline().decode("ascii", "replace").strip()
        print(f"[fpga] recognised: {line!r}")

if __name__ == "__main__":
    main()
