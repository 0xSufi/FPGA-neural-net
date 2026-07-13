// Segment walk on PMOD group B: light ONE pin at a time (active-low = segment on),
// ~2.5s each, in the fixed order pB[0]..pB[7] = C10,C11,B10,B11,D10,D11,G10,G11,
// then a long (~5s) all-dark pause to mark the start of each cycle.
module top_walk(input clk, output reg [7:0] pB);
  reg [31:0] cnt = 0;
  reg [3:0]  idx = 0;               // 0..9 (8 = pause, 9 = pause)
  localparam STEP = 32'd125_000_000; // ~2.5s @50MHz
  always @(posedge clk) begin
    if (cnt >= STEP) begin cnt <= 0; idx <= (idx==4'd9) ? 4'd0 : idx + 4'd1; end
    else cnt <= cnt + 1;
  end
  always @* begin
    pB = 8'hFF;                     // all off
    if (idx < 8) pB[idx] = 1'b0;    // light exactly one; idx 8,9 = dark pause
  end
endmodule
