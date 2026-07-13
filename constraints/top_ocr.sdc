// 50 MHz input clock on E2 (period 20 ns)
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
