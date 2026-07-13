// Static single-digit counter 0..9 on the sel=1 digit (no multiplexing), using
// the empirically-mapped group-B segment pins. Confirms the segment map alone.
module top_count(input clk, output [6:0] seg, output sel);
  reg [7:0] por=0; wire rst_n=por[7];
  always @(posedge clk) if(!por[7]) por<=por+8'd1;
  reg [31:0] cnt=0; reg [3:0] d=0;
  always @(posedge clk) begin
    if(!rst_n) begin cnt<=0; d<=0; end
    else if(cnt>=32'd60_000_000) begin cnt<=0; d<=(d==4'd9)?4'd0:d+4'd1; end
    else cnt<=cnt+1;
  end
  localparam [6:0] P0=7'b0000001,P1=7'b1111001,P2=7'b0010010,P3=7'b0110000,
                   P4=7'b1101000,P5=7'b0100100,P6=7'b0000100,P7=7'b1110001,
                   P8=7'b0000000,P9=7'b0100000;
  reg [6:0] p;
  always @* case(d) 0:p=P0;1:p=P1;2:p=P2;3:p=P3;4:p=P4;5:p=P5;6:p=P6;7:p=P7;8:p=P8;9:p=P9;default:p=7'b1111111;endcase
  assign seg = p;
  assign sel = 1'b1;
endmodule
