#!/usr/bin/env python3
"""Generate sample black-on-white digit images for the demo (send via
`send_number.py --image images/<file>.png`):
  images/digit_0.png .. digit_9.png : single digits
  images/num_10.png  .. num_99.png  : two-digit numbers
Also writes contact sheets images/digits_0-9.png and images/nums_sample.png.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import send_number as sn

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT  = os.path.join(ROOT, "images"); os.makedirs(OUT, exist_ok=True)

for d in range(10):                                   # single digits
    sn.render_number_image(d, size=90).save(f"{OUT}/digit_{d}.png")
for n in range(10, 100):                              # two-digit numbers
    sn.render_number_image(n, size=70, gap=18).save(f"{OUT}/num_{n}.png")

def sheet(imgs, path, cols):
    ims = [Image.open(p).resize((96, 72)) for p in imgs]
    rows = (len(ims) + cols - 1) // cols
    sh = Image.new("L", (cols*96, rows*72), 255)
    for i, im in enumerate(ims): sh.paste(im, ((i % cols)*96, (i//cols)*72))
    sh.save(path)

sheet([f"{OUT}/digit_{d}.png" for d in range(10)], f"{OUT}/digits_0-9.png", 10)
sheet([f"{OUT}/num_{n}.png" for n in (13, 27, 42, 55, 68, 74, 89, 90, 96, 99)],
      f"{OUT}/nums_sample.png", 5)
print(f"wrote {10} single + {90} two-digit images to images/")
