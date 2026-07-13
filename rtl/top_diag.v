// Diagnostic: internal power-on reset, heartbeat 'A' every ~0.5s on uart_tx,
// and echo of any received byte. No external reset dependency. Used to verify
// clock + UART pins + serial port independent of the OCR design.
module top_diag #(parameter CLK_FRE=50, BAUD=115200)(
    input  wire clk,
    input  wire uart_rx,
    output wire uart_tx
);
    reg [7:0] por = 8'd0;
    wire rst_n = por[7];
    always @(posedge clk) if (!por[7]) por <= por + 8'd1;

    wire [7:0] rxd; wire rxv;
    uart_rx #(.CLK_FRE(CLK_FRE), .BAUD_RATE(BAUD)) urx (
        .clk(clk), .rst_n(rst_n), .rx_data(rxd), .rx_data_valid(rxv),
        .rx_data_ready(1'b1), .rx_pin(uart_rx));

    reg rxv_d; wire rx_stb = rxv & ~rxv_d;
    reg [25:0] hb; wire hb_tick = (hb == 26'd25_000_000-1);
    reg [7:0] tx_data; reg tx_valid; wire tx_ready;
    reg [7:0] pend; reg has_pend;

    always @(posedge clk) begin
        if (!rst_n) begin
            rxv_d<=0; hb<=0; tx_valid<=0; has_pend<=0; tx_data<=0; pend<=0;
        end else begin
            rxv_d <= rxv;
            hb    <= hb_tick ? 26'd0 : hb + 26'd1;
            if (rx_stb) begin pend <= rxd; has_pend <= 1'b1; end
            if (tx_valid && tx_ready) tx_valid <= 1'b0;
            if (!tx_valid) begin
                if (has_pend)      begin tx_data<=pend;    tx_valid<=1'b1; has_pend<=1'b0; end
                else if (hb_tick)  begin tx_data<=8'h41;   tx_valid<=1'b1; end   // 'A'
            end
        end
    end

    uart_tx #(.CLK_FRE(CLK_FRE), .BAUD_RATE(BAUD)) utx (
        .clk(clk), .rst_n(rst_n), .tx_data(tx_data), .tx_data_valid(tx_valid),
        .tx_data_ready(tx_ready), .tx_pin(uart_tx));
endmodule
