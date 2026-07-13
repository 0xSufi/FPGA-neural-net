// Connector-ID: drive all 8 pins of each PMOD group; group A blinks slow,
// group B blinks fast, group C steady-on. All-pins-low lights every segment
// of one digit ("8"), so this is independent of segment order.
module top_cid(input clk,
  output [7:0] pA, output [7:0] pB, output [7:0] pC);
  reg [26:0] cnt = 0;
  always @(posedge clk) cnt <= cnt + 1'b1;
  assign pA = cnt[24] ? 8'hFF : 8'h00;   // slow blink (on when 0x00)
  assign pB = cnt[21] ? 8'hFF : 8'h00;   // fast blink (~8x faster)
  assign pC = 8'h00;                      // steady on
endmodule
