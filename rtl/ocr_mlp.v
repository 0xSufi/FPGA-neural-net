// ---------------------------------------------------------------------------
// ocr_mlp.v : full 784 -> 64 -> 10 integer MLP inference for ONE digit.
//
//   layer1 (dense_layer)  ->  ReLU + arithmetic requant (>>SHIFT1, clamp 0..127)
//   -> hidden buffer      ->  layer2 (dense_layer)  ->  argmax  ->  result[3:0]
//
// Reads the image from an external buffer (img_raddr/img_rdata), offset by
// digit_base so the same engine classifies either digit of a two-digit number.
// Pulse `start`; `done` pulses when `result` (0..9) is valid.
// ---------------------------------------------------------------------------
module ocr_mlp (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [10:0] digit_base,     // 0 for first digit, 784 for second
    output wire [10:0] img_raddr,      // read into shared image buffer
    input  wire [7:0]  img_rdata,
    output reg         done,
    output reg  [3:0]  result
);
    `include "mlp_params.vh"           // IN_DIM, HID_DIM, OUT_DIM, SHIFT1

    localparam L1_IN_AW = $clog2(IN_DIM);   // 10
    localparam L2_IN_AW = $clog2(HID_DIM);  // 6

    // ---- layer 1 ----------------------------------------------------------
    reg  l1_start;
    wire [L1_IN_AW-1:0] l1_in_addr;
    wire l1_valid, l1_done;
    wire [$clog2(HID_DIM)-1:0] l1_idx;
    wire signed [31:0] l1_acc;

    assign img_raddr = digit_base + {1'b0, l1_in_addr};

    dense_layer #(.IN_DIM(IN_DIM), .OUT_DIM(HID_DIM),
                  .WFILE("mem/w1.hex"), .BFILE("mem/b1.hex")) l1 (
        .clk(clk), .rst_n(rst_n), .start(l1_start),
        .in_addr(l1_in_addr), .in_data(img_rdata),
        .acc_valid(l1_valid), .acc_idx(l1_idx), .acc_out(l1_acc), .done(l1_done)
    );

    // ReLU + requant to int8 [0,127]
    wire signed [31:0] relu = (l1_acc[31]) ? 32'sd0 : l1_acc;
    wire signed [31:0] shft = relu >>> SHIFT1;
    wire [7:0] hval = (shft > 32'sd127) ? 8'd127 : shft[7:0];

    // ---- hidden buffer (dual access: write in L1, read in L2) -------------
    reg  [7:0] hid [0:HID_DIM-1];
    wire [L2_IN_AW-1:0] l2_in_addr;
    reg  [7:0] hid_rdata;
    always @(posedge clk) if (l1_valid) hid[l1_idx] <= hval;
    always @(posedge clk) hid_rdata <= hid[l2_in_addr];

    // ---- layer 2 ----------------------------------------------------------
    reg  l2_start;
    wire l2_valid, l2_done;
    wire [$clog2(OUT_DIM)-1:0] l2_idx;
    wire signed [31:0] l2_acc;

    dense_layer #(.IN_DIM(HID_DIM), .OUT_DIM(OUT_DIM),
                  .WFILE("mem/w2.hex"), .BFILE("mem/b2.hex")) l2 (
        .clk(clk), .rst_n(rst_n), .start(l2_start),
        .in_addr(l2_in_addr), .in_data(hid_rdata),
        .acc_valid(l2_valid), .acc_idx(l2_idx), .acc_out(l2_acc), .done(l2_done)
    );

    // ---- argmax + control -------------------------------------------------
    reg signed [31:0] best_val;
    reg [3:0]  best_idx;
    reg [1:0]  state;
    localparam C_IDLE=2'd0, C_L1=2'd1, C_L2=2'd2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=C_IDLE; l1_start<=0; l2_start<=0; done<=0; result<=0;
            best_val<=0; best_idx<=0;
        end else begin
            l1_start <= 1'b0;
            l2_start <= 1'b0;
            done     <= 1'b0;
            case (state)
                C_IDLE: if (start) begin l1_start<=1'b1; state<=C_L1; end
                C_L1: if (l1_done) begin
                          l2_start <= 1'b1;
                          best_val <= 32'sh80000000;   // -inf so any logit wins
                          best_idx <= 4'd0;
                          state    <= C_L2;
                      end
                C_L2: begin
                          if (l2_valid && (l2_acc > best_val)) begin
                              best_val <= l2_acc;
                              best_idx <= l2_idx[3:0];
                          end
                          if (l2_done) begin
                              // include the final neuron in the compare
                              result <= (l2_valid && (l2_acc > best_val)) ? l2_idx[3:0] : best_idx;
                              done   <= 1'b1;
                              state  <= C_IDLE;
                          end
                      end
                default: state <= C_IDLE;
            endcase
        end
    end
endmodule
