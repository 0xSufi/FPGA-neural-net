// Rock-steady: drive all 8 pins low = full "8" on the select-low (good) digit.
module top_static8(input clk, output [7:0] p);
  assign p = 8'h00;
endmodule
