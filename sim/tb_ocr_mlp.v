// Core-inference testbench: drives ocr_mlp with the 30 golden images and checks
// the hardware prediction matches the Python integer reference bit-for-bit.
`timescale 1ns/1ps
module tb_ocr_mlp;
    localparam IMG = 784;
    `include "count.vh"                 // N_GOLDEN

    reg clk=0, rst_n=0, start=0;
    always #10 clk = ~clk;              // 50 MHz

    // shared image buffer (only offset 0 used here; digit_base=0)
    reg  [7:0] imgmem [0:2*IMG-1];
    wire [10:0] img_raddr;
    reg  [7:0]  img_rdata;
    always @(posedge clk) img_rdata <= imgmem[img_raddr];   // 1-cycle sync read

    wire done;
    wire [3:0] result;
    ocr_mlp dut(.clk(clk), .rst_n(rst_n), .start(start), .digit_base(11'd0),
                .img_raddr(img_raddr), .img_rdata(img_rdata),
                .done(done), .result(result));

    // golden data
    reg [7:0] all_imgs [0:N_GOLDEN*IMG-1];
    reg [3:0] all_pred [0:N_GOLDEN-1];
    reg [3:0] all_lbl  [0:N_GOLDEN-1];

    integer k, p, fails, matchlbl;
    initial begin
        $readmemh("sim/golden/all_imgs.hex",  all_imgs);
        $readmemh("sim/golden/all_pred.hex",  all_pred);
        $readmemh("sim/golden/all_label.hex", all_lbl);
        fails=0; matchlbl=0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(4) @(posedge clk);

        for (k=0; k<N_GOLDEN; k=k+1) begin
            for (p=0; p<IMG; p=p+1) imgmem[p] = all_imgs[k*IMG+p];
            @(posedge clk); start<=1; @(posedge clk); start<=0;
            wait(done); @(posedge clk);
            if (result !== all_pred[k]) begin
                $display("  MISMATCH sample %0d: hw=%0d ref=%0d (true=%0d)",
                         k, result, all_pred[k], all_lbl[k]);
                fails = fails + 1;
            end
            if (result === all_lbl[k]) matchlbl = matchlbl + 1;
        end

        $display("--------------------------------------------------");
        $display("HW-vs-reference mismatches : %0d / %0d", fails, N_GOLDEN);
        $display("HW correct vs true label   : %0d / %0d", matchlbl, N_GOLDEN);
        if (fails==0) $display("RESULT: PASS (hardware == integer reference, bit-exact)");
        else          $display("RESULT: FAIL");
        $finish;
    end

    initial begin #60000000; $display("TIMEOUT"); $finish; end
endmodule
