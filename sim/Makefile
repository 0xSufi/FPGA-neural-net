# Simulate the OCR demo with Icarus Verilog.
#   make -C sim core   # core inference vs Python reference (bit-exact check)
#   make -C sim top    # full system: UART frame -> inference -> display + echo
# Recipes run from the PROJECT ROOT so $readmemh paths (mem/, sim/golden/) resolve.
IV=iverilog -g2012 -I rtl -I sim/golden

core:
	cd .. && $(IV) -o sim/core.vvp rtl/dense_layer.v rtl/ocr_mlp.v sim/tb_ocr_mlp.v && vvp sim/core.vvp

top:
	cd .. && $(IV) -o sim/top.vvp rtl/uart_rx.v rtl/uart_tx.v rtl/dense_layer.v \
	    rtl/ocr_mlp.v rtl/img_mem.v rtl/frame_rx.v rtl/seg7_2digit.v rtl/top_ocr.v \
	    sim/tb_top.v && vvp sim/top.vvp

clean:
	rm -f *.vvp
