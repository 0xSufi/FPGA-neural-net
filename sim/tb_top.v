// Full-system testbench: drive a real serial frame into top_ocr and check the
// two-digit display latches + the ASCII echo. Uses a fast baud so the 1570-byte
// frame simulates quickly; the RTL is otherwise identical to the board build.
`timescale 1ns/1ps
module tb_top;
    localparam IMG=784;
    localparam BAUD=5_000_000;               // fast sim baud
    localparam CYC =50_000_000/BAUD;         // 10 clocks per bit
    `include "count.vh"

    reg clk=0, rst=1, rx_line=1;
    always #10 clk=~clk;                      // 50 MHz

    wire uart_tx; wire [6:0] seg; wire sel;
    top_ocr #(.CLK_FRE(50), .BAUD(BAUD)) dut (
        .clk(clk), .rst(rst), .uart_rx(rx_line), .uart_tx(uart_tx),
        .seg(seg), .sel(sel)
    );

    reg [7:0] all_imgs [0:N_GOLDEN*IMG-1];
    reg [3:0] all_pred [0:N_GOLDEN-1];

    // ---- serial byte transmitter (8N1) -----------------------------------
    task send_byte(input [7:0] b); integer k; begin
        rx_line = 0; repeat(CYC) @(posedge clk);              // start
        for (k=0;k<8;k=k+1) begin rx_line=b[k]; repeat(CYC) @(posedge clk); end
        rx_line = 1; repeat(CYC) @(posedge clk);              // stop
        repeat(CYC) @(posedge clk);                           // idle gap
    end endtask

    task send_digit(input integer idx); integer p; begin
        for (p=0;p<IMG;p=p+1) send_byte(all_imgs[idx*IMG+p]);
    end endtask

    // ---- 7-seg expected pattern (mirror of seg7_2digit) ------------------
    function [6:0] pat(input [3:0] d);
        case (d)
            0:pat=7'b0000001;1:pat=7'b1111001;2:pat=7'b0010010;3:pat=7'b0110000;
            4:pat=7'b1101000;5:pat=7'b0100100;6:pat=7'b0000100;7:pat=7'b1110001;
            8:pat=7'b0000000;9:pat=7'b0100000;default:pat=7'b1111111;
        endcase
    endfunction

    integer errors=0;
    // capture TX echo
    reg [7:0] rxbuf [0:7]; integer rxn=0;
    task get_tx_byte(output [7:0] b); integer k; begin
        @(negedge uart_tx);                                   // start bit
        repeat(CYC/2) @(posedge clk);
        for (k=0;k<8;k=k+1) begin repeat(CYC) @(posedge clk); b[k]=uart_tx; end
        repeat(CYC) @(posedge clk);                           // stop
    end endtask

    reg [7:0] c0,c1,c2,c3;
    task check_seg(input [3:0] exp_tens, input [3:0] exp_ones,
                   input exp_bt, input exp_bo); begin
        // sample the multiplexed line in whichever phase is active
        @(posedge clk);
        if (sel && !exp_bt && (seg!==pat(exp_tens)))
            begin $display("  SEG tens mismatch: got %b exp %b", seg, pat(exp_tens)); errors=errors+1; end
        if (!sel && !exp_bo && (seg!==pat(exp_ones)))
            begin $display("  SEG ones mismatch: got %b exp %b", seg, pat(exp_ones)); errors=errors+1; end
    end endtask

    initial begin
        $readmemh("sim/golden/all_imgs.hex", all_imgs);
        $readmemh("sim/golden/all_pred.hex", all_pred);
        repeat(5) @(posedge clk); rst=0; repeat(5) @(posedge clk);

        // ---- Test 1: two-digit number "42" (tens=idx8 pred4, ones=idx2 pred2)
        $display("[test1] send two-digit number, expect tens=%0d ones=%0d",
                 all_pred[8], all_pred[2]);
        send_byte(8'hA5); send_byte(8'h02);
        send_digit(8); send_digit(2);
        fork
            begin get_tx_byte(c0); get_tx_byte(c1); get_tx_byte(c2); get_tx_byte(c3); end
        join
        $display("  display: tens=%0d ones=%0d blank_t=%b blank_o=%b",
                 dut.tens, dut.ones, dut.blank_tens, dut.blank_ones);
        $display("  tx echo: '%c%c' 0x%02h 0x%02h", c0, c1, c2, c3);
        if (dut.tens!==all_pred[8] || dut.ones!==all_pred[2] ||
            dut.blank_tens!==0 || dut.blank_ones!==0) begin
            $display("  LATCH mismatch"); errors=errors+1; end
        if (c0!==(8'h30+all_pred[8]) || c1!==(8'h30+all_pred[2]) ||
            c2!==8'h0d || c3!==8'h0a) begin $display("  TX echo mismatch"); errors=errors+1; end
        check_seg(all_pred[8], all_pred[2], 0, 0);

        // ---- Test 2: single-digit number (idx5 pred1) -> tens blanked
        $display("[test2] send single-digit number, expect blank tens, ones=%0d",
                 all_pred[5]);
        send_byte(8'hA5); send_byte(8'h01);
        send_digit(5);
        fork begin get_tx_byte(c0); get_tx_byte(c1); get_tx_byte(c2); end join
        $display("  display: ones=%0d blank_t=%b", dut.ones, dut.blank_tens);
        $display("  tx echo: '%c' 0x%02h 0x%02h", c0, c1, c2);
        if (dut.ones!==all_pred[5] || dut.blank_tens!==1) begin
            $display("  single-digit mismatch"); errors=errors+1; end
        if (c0!==(8'h30+all_pred[5]) || c1!==8'h0d || c2!==8'h0a) begin
            $display("  TX echo mismatch"); errors=errors+1; end
        check_seg(0, all_pred[5], 1, 0);

        $display("--------------------------------------------------");
        if (errors==0) $display("RESULT: PASS (end-to-end: UART frame -> inference -> display + echo)");
        else           $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin #200000000; $display("TIMEOUT"); $finish; end
endmodule
