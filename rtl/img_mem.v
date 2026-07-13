// ---------------------------------------------------------------------------
// img_mem.v : shared image buffer, 2 x 784 bytes (both digits of a 0..99 number).
// Simple dual-port: write side driven by the UART frame parser, read side by the
// inference engine. Registered read => 1-cycle latency (matches dense_layer).
// ---------------------------------------------------------------------------
module img_mem #(
    parameter DEPTH = 1568,
    parameter AW    = 11
)(
    input  wire            clk,
    input  wire            we,
    input  wire [AW-1:0]   waddr,
    input  wire [7:0]      wdata,
    input  wire [AW-1:0]   raddr,
    output reg  [7:0]      rdata
);
    reg [7:0] mem [0:DEPTH-1];
    always @(posedge clk) if (we) mem[waddr] <= wdata;
    always @(posedge clk) rdata <= mem[raddr];
endmodule
