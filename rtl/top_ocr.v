// ---------------------------------------------------------------------------
// top_ocr.v : Tang Primer 25K OCR demo top level.
//
//   USB-serial (BL616) --> uart_rx --> frame_rx --> img_mem
//                                                      |
//                                                   ocr_mlp  (784->64->10, x2 digits)
//                                                      |
//                                     +----------------+----------------+
//                                     |                                 |
//                              seg7_2digit (PMOD_DTx2)          uart_tx (echo "NN\r\n")
//
// Send an image of a number 0..99 over USB; the recognised value shows on the
// two-digit display and is echoed back over serial as ASCII.
// ---------------------------------------------------------------------------
// NOTE on CLK_FRE: the Tang Primer 25K fabric clock is 50 MHz (confirmed on
// hardware). However, the open-source GW5A flow (yosys+apicula) bakes a UART
// divisor 4x too small, so a CLK_FRE=50 build transmits at 460800 instead of
// 115200. Setting CLK_FRE=200 quadruples the divisor and yields a correct
// 115200 baud on hardware (verified). The SDC still constrains the real 50 MHz.
// (With the proprietary Gowin toolchain, use CLK_FRE=50.)
module top_ocr #(
    parameter CLK_FRE = 200,           // see note above (open-flow compensation; real clock 50 MHz)
    parameter BAUD    = 115200         // overridden low in simulation for speed
)(
    input  wire       clk,             // E2  50MHz
    input  wire       rst,             // H11 active-high button
    input  wire       uart_rx,         // B3  from BL616
    output wire       uart_tx,         // C3  to BL616
    output wire [6:0] seg,             // PMOD_DTx2 segments (active low)
    output wire       sel              // PMOD_DTx2 digit select
);
    wire rst_n = ~rst;

    // ---- UART receive ----------------------------------------------------
    wire [7:0] rx_data;  wire rx_valid;
    uart_rx #(.CLK_FRE(CLK_FRE), .BAUD_RATE(BAUD)) u_rx (
        .clk(clk), .rst_n(rst_n),
        .rx_data(rx_data), .rx_data_valid(rx_valid), .rx_data_ready(1'b1),
        .rx_pin(uart_rx)
    );

    // ---- frame parse + image buffer --------------------------------------
    wire        img_we;  wire [10:0] img_waddr;  wire [7:0] img_wdata;
    wire [1:0]  ndigits; wire        frame_done;
    frame_rx u_frame (
        .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid),
        .img_we(img_we), .img_waddr(img_waddr), .img_wdata(img_wdata),
        .ndigits(ndigits), .frame_done(frame_done)
    );

    wire [10:0] img_raddr;  wire [7:0] img_rdata;
    img_mem u_mem (
        .clk(clk), .we(img_we), .waddr(img_waddr), .wdata(img_wdata),
        .raddr(img_raddr), .rdata(img_rdata)
    );

    // ---- inference engine (one digit at a time) --------------------------
    reg         mlp_start;  reg [10:0] digit_base;
    wire        mlp_done;   wire [3:0] mlp_result;
    ocr_mlp u_mlp (
        .clk(clk), .rst_n(rst_n), .start(mlp_start), .digit_base(digit_base),
        .img_raddr(img_raddr), .img_rdata(img_rdata),
        .done(mlp_done), .result(mlp_result)
    );

    // ---- control: classify 1 or 2 digits, then latch + echo --------------
    localparam C_IDLE=0, C_CLS0=1, C_WAIT0=2, C_CLS1=3, C_WAIT1=4, C_LATCH=5,
               C_TXLOAD=6, C_TXSTB=7, C_TXBUSY=8, C_TXDRAIN=9;
    reg [3:0]  cstate;
    reg [1:0]  ndig_l;
    reg [3:0]  tens, ones;
    reg        blank_tens, blank_ones;

    // TX result echo
    reg  [7:0] tx_data;  reg tx_data_valid;  wire tx_data_ready;
    reg  [7:0] txbuf [0:3];
    reg  [2:0] txlen, txi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cstate<=C_IDLE; mlp_start<=0; digit_base<=0; ndig_l<=0;
            tens<=0; ones<=0; blank_tens<=1; blank_ones<=1;
            tx_data<=0; tx_data_valid<=0; txlen<=0; txi<=0;
        end else begin
            mlp_start <= 1'b0;
            case (cstate)
                C_IDLE:
                    if (frame_done) begin ndig_l<=ndigits; cstate<=C_CLS0; end
                C_CLS0: begin digit_base<=11'd0;   mlp_start<=1'b1; cstate<=C_WAIT0; end
                C_WAIT0:
                    if (mlp_done) begin
                        if (ndig_l==2'd2) begin tens<=mlp_result; cstate<=C_CLS1; end
                        else begin
                            ones<=mlp_result; blank_ones<=1'b0;
                            tens<=0; blank_tens<=1'b1;     // single digit: blank tens
                            cstate<=C_LATCH;
                        end
                    end
                C_CLS1: begin digit_base<=11'd784; mlp_start<=1'b1; cstate<=C_WAIT1; end
                C_WAIT1:
                    if (mlp_done) begin
                        ones<=mlp_result; blank_ones<=1'b0; blank_tens<=1'b0;
                        cstate<=C_LATCH;
                    end
                C_LATCH: begin
                    // build ascii echo: "NN\r\n" (or "N\r\n" for a single digit)
                    if (ndig_l==2'd2) begin
                        txbuf[0]<=8'h30+{4'd0,tens};
                        txbuf[1]<=8'h30+{4'd0,ones};
                        txbuf[2]<=8'h0d; txbuf[3]<=8'h0a; txlen<=3'd4;
                    end else begin
                        txbuf[0]<=8'h30+{4'd0,ones};
                        txbuf[1]<=8'h0d; txbuf[2]<=8'h0a; txlen<=3'd3;
                    end
                    txi<=0; cstate<=C_TXLOAD;
                end
                // single-beat valid/ready UART TX sequencer
                C_TXLOAD:
                    if (tx_data_ready) begin
                        tx_data<=txbuf[txi]; tx_data_valid<=1'b1; cstate<=C_TXSTB;
                    end
                C_TXSTB: begin tx_data_valid<=1'b0; cstate<=C_TXBUSY; end
                C_TXBUSY:  if (!tx_data_ready) cstate<=C_TXDRAIN;   // byte accepted
                C_TXDRAIN: if (tx_data_ready) begin                 // byte fully sent
                        if (txi==txlen-1) cstate<=C_IDLE;
                        else begin txi<=txi+1'b1; cstate<=C_TXLOAD; end
                    end
                default: cstate<=C_IDLE;
            endcase
        end
    end

    uart_tx #(.CLK_FRE(CLK_FRE), .BAUD_RATE(BAUD)) u_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_data(tx_data), .tx_data_valid(tx_data_valid),
        .tx_data_ready(tx_data_ready), .tx_pin(uart_tx)
    );

    // ---- display ---------------------------------------------------------
    seg7_2digit u_seg (
        .clk(clk), .rst_n(rst_n),
        .tens(tens), .ones(ones),
        .blank_tens(blank_tens), .blank_ones(blank_ones),
        .seg(seg), .sel(sel)
    );
endmodule
