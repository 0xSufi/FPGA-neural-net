// Subtractive walk: start from full "8" (all pins low), then turn OFF one pin at
// a time so exactly one bar disappears. Order slots 1..8 = pins p[0]..p[7] =
// G11,G10,D11,D10,B11,B10,C11,C10. slot0 = full 8 (reference), slot9 = dark gap.
module top_subwalk(input clk, output reg [7:0] p);
  reg [7:0] por=0; wire rst_n=por[7];
  always @(posedge clk) if(!por[7]) por<=por+8'd1;
  reg [31:0] cnt=0; reg [3:0] slot=0;
  localparam SLOT=32'd110_000_000; // ~2.2s
  always @(posedge clk) begin
    if(!rst_n) begin cnt<=0; slot<=0; end
    else if(cnt>=SLOT) begin cnt<=0; slot<=(slot==4'd9)?4'd0:slot+4'd1; end
    else cnt<=cnt+1;
  end
  always @* begin
    if(slot==4'd0) p = 8'h00;           // full 8
    else if(slot==4'd9) p = 8'hFF;      // dark gap (marks cycle end)
    else begin p = 8'h00; p[slot-4'd1] = 1'b1; end  // remove one bar
  end
endmodule
