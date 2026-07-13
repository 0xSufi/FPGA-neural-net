// Show digit "4" under 4 candidate segment orientations, one at a time (~3s),
// separated by a short blank, with a 6s blank marking the cycle start.
// p[7:0] = C10,C11,B10,B11,D10,D11,G10,G11(sel). Active-low; sel(p0)=1.
//   slot0 = identity(walk)   slot2 = 180-rotate
//   slot4 = horizontal-flip  slot6 = vertical-flip
module top_mapsearch(input clk, output reg [7:0] p);
  reg [7:0] por=0; wire rst_n=por[7];
  always @(posedge clk) if(!por[7]) por<=por+8'd1;
  reg [31:0] cnt=0; reg [3:0] slot=0;
  localparam SLOT=32'd150_000_000; // ~3s @50MHz
  always @(posedge clk) begin
    if(!rst_n) begin cnt<=0; slot<=0; end
    else if(cnt>=SLOT) begin cnt<=0; slot<=(slot==4'd8)?4'd0:slot+4'd1; end
    else cnt<=cnt+1;
  end
  always @* case(slot)
    0: p=8'h71;   // cand1 identity
    2: p=8'h59;   // cand2 180-rotate
    4: p=8'h53;   // cand3 h-flip
    6: p=8'hD1;   // cand4 v-flip
    default: p=8'hFF;  // blank
  endcase
endmodule
