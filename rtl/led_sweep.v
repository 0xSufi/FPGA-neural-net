// ---------------------------------------------------------------------------
// led_sweep.v : "knight-rider" activity indicator across 16 LEDs (two PMOD_LEDx8
// modules). Bounces a single lit LED back and forth while `busy` is high; all
// off when idle. Output `lit` is active-high logical (1 = LED on); the top level
// inverts for the active-low PMOD_LEDx8 hardware.
// ---------------------------------------------------------------------------
module led_sweep #(
    parameter STEP = 2_000_000        // clocks per LED step (~40 ms @ 50 MHz)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        busy,
    output reg  [15:0] lit
);
    reg [23:0] cnt = 0;
    reg [3:0]  pos = 0;
    reg        dir = 0;               // 0 = ascending, 1 = descending
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt<=0; pos<=0; dir<=0; lit<=16'h0000;
        end else if (!busy) begin
            cnt<=0; pos<=0; dir<=0; lit<=16'h0000;   // idle: LEDs off
        end else begin
            if (cnt >= STEP) begin
                cnt <= 0;
                if (!dir) begin
                    if (pos==4'd15) begin dir<=1'b1; pos<=4'd14; end else pos<=pos+4'd1;
                end else begin
                    if (pos==4'd0)  begin dir<=1'b0; pos<=4'd1;  end else pos<=pos-4'd1;
                end
            end else cnt <= cnt + 1'b1;
            lit <= (16'h1 << pos);
        end
    end
endmodule
