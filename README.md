# Tang Primer 25K — USB → OCR → 7-segment demo

Send an image of a number **0–99** over USB; a small neural network on the FPGA
classifies it and shows the value on the **PMOD_DTx2** two-digit display (and
echoes it back over serial).

```
 PC ──USB(115200 8N1)──► BL616 ──► uart_rx ──► frame_rx ──► img_mem (2×784 B)
                                                                │
                                                          ocr_mlp  784→64→10  (int8, run per digit)
                                                                │
                                    ┌───────────────────────────┴───────────────┐
                                    ▼                                            ▼
                          seg7_2digit → PMOD_DTx2                    uart_tx → "NN\r\n" echo
```

The recogniser is a quantised **MLP (784→64→10)** run once per digit. The host
crops/segments the number into two 28×28 tiles; the FPGA classifies each and
combines them (leading-zero blanked for single-digit numbers).

## Status — WORKING ON HARDWARE

| Check | Result |
|---|---|
| Quantised model accuracy (Python int) | MNIST **96.1%**, printed digits **92.3%** |
| RTL vs Python integer reference (`make -C sim core`) | **0/30 mismatches — bit-exact** |
| Full system UART→infer→display→echo (`make -C sim top`) | **PASS** |
| Host render → integer ROMs, all numbers 0–99 | **100/100 correct** |
| **On real Tang Primer 25K, live USB→net→tube, 0–99** | **100/100 correct** |

Built with the **open-source flow** (OSS CAD Suite: yosys + nextpnr-himbaechel +
apicula + openFPGALoader) — no proprietary Gowin toolchain needed. See `build.sh`.

## Layout

```
rtl/    dense_layer.v   generic sequential int8 MAC engine (1 DSP)
        ocr_mlp.v       layer1 → ReLU/requant → layer2 → argmax (one digit)
        frame_rx.v      0xA5 | ndigits | pixels  protocol parser
        img_mem.v       shared 2×784-byte image buffer
        seg7_2digit.v   PMOD_DTx2 driver (vendor segment table, active-low, muxed)
        top_ocr.v       top level + 2-digit control FSM + ASCII echo
        uart_rx/tx.v    Sipeed's known-good UART (verbatim)
        mlp_params.vh   generated: IN/HID/OUT dims + SHIFT1
mem/    w1,b1,w2,b2.hex generated int8/int32 ROM images ($readmemh)
constraints/  top_ocr.cst  pin map (E2 clk, H11 rst, B3/C3 uart, K5+seg pins)
              top_ocr.sdc  50 MHz clock
host/   train_export.py train+quantize+export;  send_number.py sender;
        infer_ref.py    pure-python integer inference from the ROMs
sim/    tb_ocr_mlp.v (core), tb_top.v (system), golden/ vectors, Makefile
```

## Build & run

### 1. Train / quantize / export  (regenerates mem/*.hex, params, golden)
```bash
pip install -r host/requirements.txt
python3 host/train_export.py
```

### 2. Simulate (proves the RTL matches the model)
```bash
make -C sim core     # bit-exact check vs Python
make -C sim top      # full UART→display→echo
```

### 3. Synthesize + program (open-source flow)
```bash
./build.sh            # yosys -> nextpnr -> gowin_pack -> openFPGALoader (SRAM)
./build.sh diag       # UART diagnostic bitstream (heartbeat 'A' + echo)
```
Needs OSS CAD Suite on PATH (`source .../oss-cad-suite/environment`). **Plug the
PMOD_DTx2 into the slot matching Sipeed's `pmod_digitalTube-2bit` mapping** (sel=K5,
seg=L11/K11/L5/E10/E11/A11/A10) — i.e. NOT the SD-card slot next to USB-C and NOT
the USB-A/HDMI-side slot, but the third one. On any other slot the segment order is
wrong and it shows garbage. Verify with `./build.sh` after flashing
`build/top_ocr.fs`, then `--render 42` → the tube shows 42. Open-flow GW5A
specifics (all handled in `build.sh`): `synth_gowin -nodsp
-nolutram`, device `GW5A-LV25MG121NES` / gowin_pack `-d GW5A-25A`, and
`sspi_as_gpio` on both tools. SRAM load is volatile — re-run after a power cycle.

> **UART baud:** the open flow bakes the divisor 4× too small, so `top_ocr` is
> built with `CLK_FRE=200` to get a correct **115200** (real clock is 50 MHz).
> With the proprietary Gowin toolchain, set `CLK_FRE=50` instead.

### 4. Send a number
Run host scripts with a Python that has numpy/pillow/pyserial (NOT the OSS CAD
Suite python):
```bash
python3 host/send_number.py --port /dev/ttyUSB1 --render 42      # renders "42"
python3 host/send_number.py --port /dev/ttyUSB1 --image scan.png # segments an image
python3 host/send_number.py --render 7 --dry                     # preview, no board
```
The tube shows the number; the host prints the FPGA's echoed value. (`/dev/ttyUSB1`
is the FT2232 UART; interface 0 / ttyUSB0 is JTAG.)

## Resource / performance estimate (GW5A-25)

| Resource | Used (approx) | Available | Note |
|---|---|---|---|
| BSRAM | ~0.42 Mbit | 1.0 Mbit | dominated by w1 ROM (50176×8) |
| DSP | 2 | 28 | one 8×8 MAC per dense_layer |
| LUT4 / FF | a few k | 23,040 | control + UART + display |
| Fmax | 50 MHz target | — | trivially met |

Inference latency ≈ **~2 ms per number** (~50k cycles/digit at 50 MHz). End-to-end
throughput is limited by the USB transfer (~136 ms for a 2-digit frame at 115200),
not by the network — plenty for an interactive demo.

## Protocol

```
byte 0   : 0xA5              (sync)
byte 1   : 0x01 or 0x02      (number of digit tiles)
then     : ndigits × 784 bytes, row-major 28×28, tens digit first,
           each byte 0 (background) or non-zero (ink)
reply    : ASCII "NN\r\n" (or "N\r\n" for a single digit)
```

## Notes / where to tune
- **Accuracy on printed digits** (~92%) improves with more epochs, more fonts, or
  matching the exact font/size you'll actually send. Retrain via step 1.
- **Hidden size / requant** live in `host/train_export.py` (`HID_DIM`, `SHIFT1`
  auto-picked); the RTL adapts via `rtl/mlp_params.vh`.
- The MAC engine is sequential (1 DSP). If you ever want more throughput, widen
  `dense_layer` to process several inputs per cycle — there are 28 DSPs to spare.
```
