// Display connector probe: drives a DIFFERENT number on each of the 3 PMOD pin
// groups from Sipeed's pmod_digitalTube-2bit example, so whichever connector the
// PMOD_DTx2 is plugged into reveals itself:
//     group A (example "digital tube" pins) -> "11"
//     group B (example "LED"        pins)   -> "22"
//     group C (example "button/sw"  pins)   -> "33"
// No UART; internal power-on reset. Purely to find the right connector.
module top_probe (
    input  wire clk,
    output wire [6:0] segA, output wire selA,
    output wire [6:0] segB, output wire selB,
    output wire [6:0] segC, output wire selC
);
    reg [7:0] por = 8'd0;
    wire rst_n = por[7];
    always @(posedge clk) if (!por[7]) por <= por + 8'd1;

    seg7_2digit uA(.clk(clk),.rst_n(rst_n),.tens(4'd1),.ones(4'd1),
                   .blank_tens(1'b0),.blank_ones(1'b0),.seg(segA),.sel(selA));
    seg7_2digit uB(.clk(clk),.rst_n(rst_n),.tens(4'd2),.ones(4'd2),
                   .blank_tens(1'b0),.blank_ones(1'b0),.seg(segB),.sel(selB));
    seg7_2digit uC(.clk(clk),.rst_n(rst_n),.tens(4'd3),.ones(4'd3),
                   .blank_tens(1'b0),.blank_ones(1'b0),.seg(segC),.sel(selC));
endmodule
