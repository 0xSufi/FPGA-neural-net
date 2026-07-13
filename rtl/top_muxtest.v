// Slow manual mux: hold select=0 showing "2" for ~2s, then select=1 showing "5"
// for ~2s, and repeat. Lets us see each digit's content separately.
module top_muxtest(input clk, output reg [6:0] seg, output reg sel);
  reg [7:0] por=0; wire rst_n=por[7];
  always @(posedge clk) if(!por[7]) por<=por+8'd1;
  reg [31:0] cnt=0; reg phase=0;
  always @(posedge clk) begin
    if(!rst_n) begin cnt<=0; phase<=0; end
    else if(cnt>=32'd100_000_000) begin cnt<=0; phase<=~phase; end
    else cnt<=cnt+1;
  end
  localparam [6:0] P2=7'b0010010, P5=7'b0100100;
  always @* begin
    sel = phase;                 // phase0: sel=0 ("2"), phase1: sel=1 ("5")
    seg = phase ? P5 : P2;
  end
endmodule
