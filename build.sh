#!/usr/bin/env bash
# Open-source build + flash for the Tang Primer 25K OCR demo.
# Uses OSS CAD Suite (yosys + nextpnr-himbaechel + apicula + openFPGALoader).
# Run from the project root:   ./build.sh [diag]
#   (no arg) -> build & flash the OCR design (top_ocr)
#   diag     -> build & flash the UART diagnostic (top_diag)
set -e
source /home/binyu/tools/oss-cad-suite/environment 2>/dev/null || \
    export PATH=/home/binyu/tools/oss-cad-suite/bin:$PATH

DEV="GW5A-LV25MG121NES"     # nextpnr device (full part/package)
PACKDEV="GW5A-25A"          # apicula gowin_pack device
BOARD="tangprimer25k"
mkdir -p build

if [ "$1" = "diag" ]; then
    TOP=top_diag; CST=constraints/diag.cst
    SRC="rtl/uart_rx.v rtl/uart_tx.v rtl/top_diag.v"
else
    TOP=top_ocr;  CST=constraints/top_ocr.cst
    SRC="rtl/uart_rx.v rtl/uart_tx.v rtl/dense_layer.v rtl/ocr_mlp.v \
         rtl/img_mem.v rtl/frame_rx.v rtl/seg7_2digit.v rtl/top_ocr.v"
fi
FS=build/$TOP.fs

# GW5A open-flow notes:
#  -nodsp     : GW5A DSP (MULT) BELs not yet placeable -> multiply in LUTs
#  -nolutram  : GW5A LUT-RAM (SDP) not yet placeable   -> small RAM in FF/BSRAM
#  sspi_as_gpio (both tools) : GW5A-25A requires SSPI config pins freed as GPIO
echo "### yosys ($TOP)"
yosys -p "read_verilog $SRC; synth_gowin -nodsp -nolutram -top $TOP -json build/$TOP.json" \
      > build/$TOP.yosys.log 2>&1
echo "### nextpnr"
nextpnr-himbaechel --json build/$TOP.json --write build/$TOP.pnr.json \
    --device "$DEV" --vopt cst=$CST --vopt sspi_as_gpio > build/$TOP.pnr.log 2>&1
grep -iE 'IOB|LUT4|BSRAM|DFF' build/$TOP.pnr.log | grep -E '[0-9]+/' | head
echo "### gowin_pack"
gowin_pack -d "$PACKDEV" --sspi_as_gpio -o "$FS" build/$TOP.pnr.json > build/$TOP.pack.log 2>&1
echo "### flash $FS -> $BOARD (SRAM)"
openFPGALoader -b "$BOARD" "$FS"
echo "### done: $FS"
