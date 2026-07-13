#!/usr/bin/env python3
"""
Pure-Python integer inference using the EXACT exported ROMs (mem/*.hex) and
requant shift (rtl/mlp_params.vh). This is the same integer math the FPGA runs,
so it lets you sanity-check weights / preprocessing without the board.

  from infer_ref import load, infer
  net = load(); digit = infer(net, tile_784)
"""
import os, re, numpy as np
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def _read_hex(path, signed_bits):
    vals = []
    for ln in open(path):
        ln = ln.strip()
        if not ln: continue
        v = int(ln, 16)
        if signed_bits and v >= (1 << (signed_bits-1)): v -= (1 << signed_bits)
        vals.append(v)
    return np.array(vals, dtype=np.int64)

def load():
    p = open(os.path.join(ROOT, "rtl", "mlp_params.vh")).read()
    g = lambda k: int(re.search(rf"{k}\s*=\s*(\d+)", p).group(1))
    IN, H, O, S = g("IN_DIM"), g("HID_DIM"), g("OUT_DIM"), g("SHIFT1")
    m = lambda f: os.path.join(ROOT, "mem", f)
    return dict(
        IN=IN, H=H, O=O, S=S,
        W1=_read_hex(m("w1.hex"), 8).reshape(H, IN),
        b1=_read_hex(m("b1.hex"), 32),
        W2=_read_hex(m("w2.hex"), 8).reshape(O, H),
        b2=_read_hex(m("b2.hex"), 32),
    )

def infer(net, x):
    x = (np.asarray(x).reshape(-1) != 0).astype(np.int64)
    acc1 = net["W1"] @ x + net["b1"]
    h    = np.clip(np.maximum(acc1, 0) >> net["S"], 0, 127)
    acc2 = net["W2"] @ h + net["b2"]
    return int(np.argmax(acc2))

if __name__ == "__main__":
    import sys
    net = load()
    if len(sys.argv) > 1:                      # classify a golden img file
        x = [int(l, 16) for l in open(sys.argv[1]) if l.strip()]
        print("digit =", infer(net, x))
    else:
        print(f"loaded MLP {net['IN']}->{net['H']}->{net['O']} SHIFT1={net['S']}")
