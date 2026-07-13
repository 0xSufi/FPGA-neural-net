#!/usr/bin/env python3
"""
Train a tiny MLP digit classifier (28x28 -> 64 -> 10), quantize it to a pure
INTEGER pipeline, and export everything the FPGA needs:

  mem/w1.hex  mem/b1.hex  mem/w2.hex  mem/b2.hex   ($readmemh ROM images)
  rtl/mlp_params.vh                                (dims + requant shift)
  sim/golden/img_XX.hex , sim/golden/labels.txt    (bit-exact test vectors)

The integer reference implemented here (`infer_int`) is the SPEC the Verilog
must reproduce exactly.  Nothing floating point runs on the FPGA.

Quantization scheme (symmetric, per-tensor, argmax-preserving):
  input x in {0,1}
  layer1:  acc1 = W1q @ x + b1q                      (int)
           h    = clip( relu(acc1) >> SHIFT1, 0, 127)(int8, >=0)
  layer2:  acc2 = W2q @ h + b2q                      (int)
           pred = argmax(acc2)
Because every scale factor is a positive constant, argmax over the integer
accumulators equals argmax over the real-valued logits.
"""
import os, glob, struct
import numpy as np
import torch, torch.nn as nn, torch.nn.functional as F

ROOT   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEM    = os.path.join(ROOT, "mem")
RTL    = os.path.join(ROOT, "rtl")
GOLD   = os.path.join(ROOT, "sim", "golden")
for d in (MEM, RTL, GOLD): os.makedirs(d, exist_ok=True)

IN_DIM, HID_DIM, OUT_DIM = 28*28, 64, 10
DEV = "cuda" if torch.cuda.is_available() else "cpu"
torch.manual_seed(0); np.random.seed(0)

# --------------------------------------------------------------------------
# Data: MNIST (if downloadable) + PIL-rendered printed digits (always).
# Everything is binarized to {0,1} at threshold 0.5 to match the FPGA input.
# --------------------------------------------------------------------------
def binarize(t):                       # t: float tensor in [0,1]
    return (t > 0.5).float()

def load_mnist():
    try:
        from torchvision import datasets, transforms
        tf = transforms.ToTensor()
        tr = datasets.MNIST(os.path.join(ROOT, "host", ".data"), train=True,  download=True, transform=tf)
        te = datasets.MNIST(os.path.join(ROOT, "host", ".data"), train=False, download=True, transform=tf)
        def to_xy(ds):
            X = torch.stack([binarize(ds[i][0][0]) for i in range(len(ds))]).view(len(ds), -1)
            y = torch.tensor([ds[i][1] for i in range(len(ds))])
            return X, y
        print("[data] MNIST loaded")
        return to_xy(tr), to_xy(te)
    except Exception as e:
        print(f"[data] MNIST unavailable ({e}); using rendered digits only")
        return None, None

def render_digits(n_per_class=1000):
    """Printed-digit samples. Two styles are mixed so the net is robust to BOTH
    demo paths: (a) small direct render (--render), and (b) render-large-then-
    downsample+threshold, which matches host/send_number.py image_to_tiles (--image)."""
    from PIL import Image, ImageDraw, ImageFont
    fonts = []
    for p in sorted(glob.glob("/usr/share/fonts/truetype/**/*.ttf", recursive=True)):
        low = p.lower()
        if any(k in low for k in ("sans", "mono", "serif")) and "math" not in low:
            fonts.append(p)
    fonts = fonts[:8] or [None]
    X, y = [], []
    rng = np.random.default_rng(1)

    def font_at(fp, sz):
        try: return ImageFont.truetype(fp, sz) if fp else ImageFont.load_default()
        except Exception: return ImageFont.load_default()

    for d in range(10):
        s = str(d)
        for k in range(n_per_class):
            fp = fonts[k % len(fonts)]
            jx = int(rng.integers(-2, 3)); jy = int(rng.integers(-2, 3))
            if k % 2 == 0:                                   # (a) small direct render
                font = font_at(fp, int(rng.integers(18, 26)))
                img = Image.new("L", (28, 28), 0); drw = ImageDraw.Draw(img)
                try:
                    bb = drw.textbbox((0,0), s, font=font); tw,th=bb[2]-bb[0],bb[3]-bb[1]; ox,oy=-bb[0],-bb[1]
                except Exception: tw,th,ox,oy = 12,18,0,0
                drw.text(((28-tw)//2+ox+jx, (28-th)//2+oy+jy), s, fill=255, font=font)
                thr = 0.5
            else:                                            # (b) large -> downsample (image_to_tiles-like)
                big = int(rng.integers(50, 110)); font = font_at(fp, big)
                canv = Image.new("L", (big*2, big*2), 0); dd = ImageDraw.Draw(canv)
                try:
                    bb = dd.textbbox((0,0), s, font=font); ox,oy=-bb[0],-bb[1]
                except Exception: ox,oy = 0,0
                dd.text((12+ox, 12+oy), s, fill=255, font=font)
                a2 = np.asarray(canv); ys,xs = np.where(a2 > 40)
                if len(xs)==0: continue
                crop = canv.crop((int(xs.min()), int(ys.min()), int(xs.max())+1, int(ys.max())+1))
                h = int(rng.integers(16, 25)); w = max(1, min(26, round(crop.width*h/crop.height)))
                small = crop.resize((w, h), Image.BILINEAR)
                img = Image.new("L", (28, 28), 0)
                img.paste(small, ((28-w)//2+jx, (28-h)//2+jy))
                thr = float(rng.uniform(0.35, 0.6))
            a = (np.asarray(img, np.float32)/255.0 > thr).astype(np.float32)
            X.append(a.reshape(-1)); y.append(d)
    X = torch.tensor(np.stack(X)); y = torch.tensor(y)
    print(f"[data] rendered {len(y)} printed-digit samples ({len(fonts)} fonts, 2 styles)")
    return X, y

(mn_tr, mn_te) = load_mnist()
rd_X, rd_y = render_digits()
# split rendered into train/test
perm = torch.randperm(len(rd_y)); rd_X, rd_y = rd_X[perm], rd_y[perm]
cut = int(0.9*len(rd_y))
rd_trX, rd_trY, rd_teX, rd_teY = rd_X[:cut], rd_y[:cut], rd_X[cut:], rd_y[cut:]

if mn_tr is not None:
    trX = torch.cat([mn_tr[0], rd_trX]); trY = torch.cat([mn_tr[1], rd_trY])
    teX, teY = mn_te[0], mn_te[1]                 # evaluate on MNIST test
    teX2, teY2 = rd_teX, rd_teY                    # and on printed test
else:
    trX, trY, teX, teY = rd_trX, rd_trY, rd_teX, rd_teY
    teX2, teY2 = rd_teX, rd_teY

# --------------------------------------------------------------------------
# Model
# --------------------------------------------------------------------------
class MLP(nn.Module):
    def __init__(s):
        super().__init__()
        s.fc1 = nn.Linear(IN_DIM, HID_DIM)
        s.fc2 = nn.Linear(HID_DIM, OUT_DIM)
    def forward(s, x):
        return s.fc2(F.relu(s.fc1(x)))

net = MLP().to(DEV)
opt = torch.optim.Adam(net.parameters(), 1e-3)
trX_d, trY_d = trX.to(DEV), trY.to(DEV)
N, BS = len(trY_d), 256
for ep in range(8):
    net.train(); idx = torch.randperm(N, device=DEV)
    for b in range(0, N, BS):
        j = idx[b:b+BS]
        opt.zero_grad()
        loss = F.cross_entropy(net(trX_d[j]), trY_d[j])
        loss.backward(); opt.step()
    net.eval()
    with torch.no_grad():
        a1 = (net(teX.to(DEV)).argmax(1).cpu() == teY).float().mean().item()
        a2 = (net(teX2.to(DEV)).argmax(1).cpu() == teY2).float().mean().item()
    print(f"[train] epoch {ep}  loss {loss.item():.3f}  acc(mnist/printed) {a1:.3f}/{a2:.3f}")

# --------------------------------------------------------------------------
# Quantize to integers
# --------------------------------------------------------------------------
W1f = net.fc1.weight.detach().cpu().numpy().astype(np.float64)   # [H,IN]
b1f = net.fc1.bias.detach().cpu().numpy().astype(np.float64)     # [H]
W2f = net.fc2.weight.detach().cpu().numpy().astype(np.float64)   # [OUT,H]
b2f = net.fc2.bias.detach().cpu().numpy().astype(np.float64)     # [OUT]

def qtensor(Wf):
    s = np.abs(Wf).max() / 127.0
    Wq = np.clip(np.round(Wf / s), -127, 127).astype(np.int64)
    return Wq, s

W1q, s1 = qtensor(W1f)
W2q, s2 = qtensor(W2f)
b1q = np.round(b1f / s1).astype(np.int64)                        # int, layer1 domain

# choose SHIFT1 so relu(acc1) >> SHIFT1 lands in ~[0,127] over a calib set
calib = trX[:4000].numpy().astype(np.int64)                     # [Nc, IN] of 0/1
acc1_c = calib @ W1q.T + b1q                                     # [Nc, H]
mx = int(np.maximum(acc1_c, 0).max())
SHIFT1 = max(0, int(np.ceil(np.log2((mx + 1) / 127.0)))) if mx > 0 else 0
s_h1 = s1 * (2 ** SHIFT1)                                        # scale of hidden activations
b2q = np.round(b2f / (s2 * s_h1)).astype(np.int64)              # int, layer2 domain
print(f"[quant] SHIFT1={SHIFT1}  max_relu_acc1={mx}  "
      f"|b1q|max={np.abs(b1q).max()}  |b2q|max={np.abs(b2q).max()}")

# --------------------------------------------------------------------------
# Integer reference == the exact spec the Verilog must match
# --------------------------------------------------------------------------
def infer_int(x):                 # x: int array [IN] of 0/1
    acc1 = W1q @ x + b1q                               # [H]
    h    = np.clip(np.maximum(acc1, 0) >> SHIFT1, 0, 127)
    acc2 = W2q @ h + b2q                               # [OUT]
    return int(np.argmax(acc2)), acc1, h, acc2

def acc_on(X, y):
    Xi = X.numpy().astype(np.int64)
    pred = np.array([infer_int(Xi[i])[0] for i in range(len(y))])
    return (pred == y.numpy()).mean()
print(f"[quant] INT accuracy  mnist={acc_on(teX,teY):.3f}  printed={acc_on(teX2,teY2):.3f}")

# --------------------------------------------------------------------------
# Export ROM images
# --------------------------------------------------------------------------
def w8(v):  return f"{int(v) & 0xFF:02x}"
def w32(v): return f"{int(v) & 0xFFFFFFFF:08x}"

with open(os.path.join(MEM, "w1.hex"), "w") as f:      # addr = n*IN + i
    for n in range(HID_DIM):
        for i in range(IN_DIM): f.write(w8(W1q[n, i]) + "\n")
with open(os.path.join(MEM, "b1.hex"), "w") as f:
    for n in range(HID_DIM): f.write(w32(b1q[n]) + "\n")
with open(os.path.join(MEM, "w2.hex"), "w") as f:      # addr = k*HID + j
    for k in range(OUT_DIM):
        for j in range(HID_DIM): f.write(w8(W2q[k, j]) + "\n")
with open(os.path.join(MEM, "b2.hex"), "w") as f:
    for k in range(OUT_DIM): f.write(w32(b2q[k]) + "\n")

with open(os.path.join(RTL, "mlp_params.vh"), "w") as f:
    f.write("// AUTO-GENERATED by host/train_export.py -- do not edit\n")
    f.write(f"localparam IN_DIM  = {IN_DIM};\n")
    f.write(f"localparam HID_DIM = {HID_DIM};\n")
    f.write(f"localparam OUT_DIM = {OUT_DIM};\n")
    f.write(f"localparam SHIFT1  = {SHIFT1};\n")

# --------------------------------------------------------------------------
# Golden vectors for RTL simulation: pick a spread of test digits
# --------------------------------------------------------------------------
def dump_golden(X, y, tag, count):
    lines = []
    picks = []
    per = {}
    Xi = X.numpy().astype(np.int64)
    for i in range(len(y)):
        d = int(y[i])
        if per.get(d, 0) < count:
            per[d] = per.get(d, 0) + 1; picks.append(i)
        if len(picks) >= count*10: break
    for k, i in enumerate(picks):
        pred, _, _, _ = infer_int(Xi[i])
        name = f"img_{tag}_{k:02d}.hex"
        with open(os.path.join(GOLD, name), "w") as f:
            for v in Xi[i]: f.write(f"{int(v):02x}\n")
        lines.append(f"{name} {pred} {int(y[i])}")
    return lines

gl = []
gl += dump_golden(teX2, teY2, "prn", 2)      # printed digits (the demo case)
if mn_te is not None:
    gl += dump_golden(teX, teY, "mn", 1)     # a few MNIST too
with open(os.path.join(GOLD, "labels.txt"), "w") as f:
    f.write("\n".join(gl) + "\n")
print(f"[export] wrote {len(gl)} golden vectors -> sim/golden/labels.txt")
print("[export] done: mem/*.hex, rtl/mlp_params.vh, sim/golden/*")
