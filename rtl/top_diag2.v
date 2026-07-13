// Diagnostic: show 4 things in sequence (long dark gap marks start):
//  1) all 7 segments ON, sel=1  -> should be "8" on digit-A
//  2) all 7 segments ON, sel=0  -> should be "8" on digit-B
//  3) walk-"4" pattern, sel=1
//  4) walk-"4" pattern, sel=0
// p[7:0]=C10,C11,B10,B11,D10,D11,G10,G11(sel). Active-low.
module top_diag2(input clk, output reg [7:0] p);
  reg [7:0] por=0; wire rst_n=por[7];
  always @(posedge clk) if(!por[7]) por<=por+8'd1;
  reg [31:0] cnt=0; reg [3:0] slot=0;
  localparam SLOT=32'd150_000_000;
  always @(posedge clk) begin
    if(!rst_n) begin cnt<=0; slot<=0; end
    else if(cnt>=SLOT) begin cnt<=0; slot<=(slot==4'd8)?4'd0:slot+4'd1; end
    else cnt<=cnt+1;
  end
  always @* case(slot)
    0: p=8'h01;   // all segs on, sel=1
    2: p=8'h00;   // all segs on, sel=0
    4: p=8'h71;   // walk "4", sel=1
    6: p=8'h70;   // walk "4", sel=0
    default: p=8'hFF; // blank
  endcase
endmodule
