// Static "31" via the real seg7_2digit multiplexed driver + confirmed pin map.
module top_show31(input clk, output [6:0] seg, output sel);
  reg [7:0] por=0; wire rst_n=por[7];
  always @(posedge clk) if(!por[7]) por<=por+8'd1;
  seg7_2digit u(.clk(clk),.rst_n(rst_n),.tens(4'd3),.ones(4'd1),
                .blank_tens(1'b0),.blank_ones(1'b0),.seg(seg),.sel(sel));
endmodule
