// Vendor slot-A mapping (pmod_digitalTube-2bit): rolling counter 00,11,..99
module top_countA(input clk, output [6:0] seg, output sel);
  reg [7:0] por=0; wire rst_n=por[7];
  always @(posedge clk) if(!por[7]) por<=por+8'd1;
  reg [31:0] cnt=0; reg [3:0] d=0;
  always @(posedge clk) begin
    if(!rst_n) begin cnt<=0; d<=0; end
    else if(cnt>=32'd50_000_000) begin cnt<=0; d<=(d==4'd9)?4'd0:d+4'd1; end
    else cnt<=cnt+1;
  end
  seg7_2digit u(.clk(clk),.rst_n(rst_n),.tens(d),.ones(d),
                .blank_tens(1'b0),.blank_ones(1'b0),.seg(seg),.sel(sel));
endmodule
