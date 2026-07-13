// ---------------------------------------------------------------------------
// seg7_2digit.v : drives the Sipeed PMOD_DTx2 two-digit 7-segment module.
//
// The module is DIRECT-DRIVEN and time-multiplexed: 7 active-low segment lines
// shared by both digits, plus one digit-select line. Segment patterns and the
// sel polarity are taken verbatim from Sipeed's driver_DigitalTube.v example
// (bit order ABCDEFG, 0 = segment lit). sel=1 shows the tens digit.
// ---------------------------------------------------------------------------
module seg7_2digit #(
    parameter P_CNT = 25000            // 50MHz/25000 -> 0.5ms per digit (~1kHz refresh)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] tens,            // 0..9
    input  wire [3:0] ones,            // 0..9
    input  wire       blank_tens,      // 1 -> tens digit dark (leading-zero blanking)
    input  wire       blank_ones,
    output wire [6:0] seg,             // active-low segments, ABCDEFG
    output wire       sel              // digit select (1=tens, 0=ones)
);
    localparam [6:0] P_0=7'b0000001, P_1=7'b1111001, P_2=7'b0010010,
                     P_3=7'b0110000, P_4=7'b1101000, P_5=7'b0100100,
                     P_6=7'b0000100, P_7=7'b1110001, P_8=7'b0000000,
                     P_9=7'b0100000, P_X=7'b1111111;   // P_X = blank

    function [6:0] pat(input [3:0] d, input blank);
        begin
            if (blank) pat = P_X;
            else case (d)
                4'd0: pat=P_0; 4'd1: pat=P_1; 4'd2: pat=P_2; 4'd3: pat=P_3;
                4'd4: pat=P_4; 4'd5: pat=P_5; 4'd6: pat=P_6; 4'd7: pat=P_7;
                4'd8: pat=P_8; 4'd9: pat=P_9; default: pat=P_X;
            endcase
        end
    endfunction

    reg [$clog2(P_CNT+1)-1:0] cnt;
    reg sel_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin cnt<=0; sel_r<=0; end
        else if (cnt==P_CNT) begin cnt<=0; sel_r<=~sel_r; end
        else cnt<=cnt+1'b1;
    end

    assign sel = sel_r;
    assign seg = sel_r ? pat(tens, blank_tens) : pat(ones, blank_ones);
endmodule
