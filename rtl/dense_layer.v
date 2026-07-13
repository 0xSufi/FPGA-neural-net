// ---------------------------------------------------------------------------
// dense_layer.v : sequential int8 fully-connected (matrix-vector) engine.
//
// Computes, for each output neuron n:  acc_out[n] = SUM_i( W[n][i] * x[i] ) + b[n]
// One multiply-accumulate per clock. Weights (int8) and biases (int32) live in
// on-chip ROMs initialised from $readmemh files. The input activation vector is
// read from an EXTERNAL synchronous memory (1-cycle read latency) via in_addr /
// in_data, so the same engine serves layer1 (from the image buffer) and layer2
// (from the hidden buffer).
//
// Results stream out one neuron at a time: when acc_valid=1, acc_out holds the
// int32 accumulator for neuron acc_idx. done pulses with the final neuron.
// ---------------------------------------------------------------------------
module dense_layer #(
    parameter IN_DIM  = 784,
    parameter OUT_DIM = 64,
    parameter WFILE   = "mem/w1.hex", // IN_DIM*OUT_DIM lines, int8 hex, addr = n*IN_DIM + i
    parameter BFILE   = "mem/b1.hex"  // OUT_DIM lines, int32 hex (run tools from project root)
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       start,
    // external activation memory read port (registered, 1-cycle latency)
    output wire [IN_AW-1:0]           in_addr,
    input  wire [7:0]                 in_data,
    // streaming result
    output reg                        acc_valid,
    output reg  [OUT_AW-1:0]          acc_idx,
    output reg  signed [31:0]         acc_out,
    output reg                        done
);
    localparam IN_AW   = $clog2(IN_DIM);
    localparam OUT_AW  = $clog2(OUT_DIM);
    localparam W_DEPTH = IN_DIM*OUT_DIM;
    localparam W_AW    = $clog2(W_DEPTH);

    // ---- ROMs -------------------------------------------------------------
    (* ram_style = "block" *) reg signed [7:0]  wrom [0:W_DEPTH-1];
    reg signed [31:0] brom [0:OUT_DIM-1];
    initial begin
        $readmemh(WFILE, wrom);
        $readmemh(BFILE, brom);
    end

    // ---- index / address generation --------------------------------------
    reg  [IN_AW:0]  i;         // issue pointer 0..IN_DIM
    reg  [OUT_AW:0] n;         // neuron index
    reg  [W_AW-1:0] wbase;     // n*IN_DIM (running, no multiplier)
    reg  [1:0]      state;
    localparam S_IDLE = 2'd0, S_RUN = 2'd1, S_EMIT = 2'd2;

    wire issue_now = (state == S_RUN) && (i < IN_DIM);
    wire last_now  = (state == S_RUN) && (i == IN_DIM-1);

    assign in_addr = i[IN_AW-1:0];
    wire [W_AW-1:0] w_addr = wbase + i;   // i is zero-extended to W_AW bits

    // registered ROM reads (1-cycle latency, aligned with in_data)
    reg signed [7:0]  wq;
    reg signed [31:0] bq;
    always @(posedge clk) begin
        wq <= wrom[w_addr];
        bq <= brom[n[OUT_AW-1:0]];
    end

    // data-valid pipeline (1 cycle after an address is issued)
    reg issue_d, last_d;
    wire signed [15:0] prod = $signed(wq) * $signed(in_data);
    reg signed [31:0] acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; i<=0; n<=0; wbase<=0;
            issue_d<=0; last_d<=0; acc<=0;
            acc_valid<=0; acc_idx<=0; acc_out<=0; done<=0;
        end else begin
            acc_valid <= 1'b0;
            done      <= 1'b0;

            // pipeline + accumulate (data for address issued last cycle)
            issue_d <= issue_now;
            last_d  <= last_now;
            if (issue_d)
                acc <= acc + prod;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        n<=0; wbase<=0; i<=0; acc<=0;
                        issue_d<=0; last_d<=0;
                        state<=S_RUN;
                    end
                end
                S_RUN: begin
                    if (issue_now) i <= i + 1'b1;
                    if (last_d)    state <= S_EMIT;   // final product accumulated this cycle
                end
                S_EMIT: begin
                    acc_out   <= acc + bq;
                    acc_idx   <= n[OUT_AW-1:0];
                    acc_valid <= 1'b1;
                    if (n == OUT_DIM-1) begin
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        n     <= n + 1'b1;
                        wbase <= wbase + IN_DIM[W_AW-1:0];
                        i     <= 0;
                        acc   <= 0;
                        issue_d<=0; last_d<=0;
                        state <= S_RUN;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
