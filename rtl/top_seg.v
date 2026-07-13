module top_seg(input clk, output reg [7:0] p);
  reg [4:0] c=0; always @(posedge clk) c<=c+5'd1;
  wire on=(c<5'd8);
  always @* begin p=8'hFF; p[0]=1'b0; if(on) p[7]=1'b0; end
endmodule
