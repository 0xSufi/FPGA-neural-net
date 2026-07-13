// ---------------------------------------------------------------------------
// frame_rx.v : parses the host protocol from the UART byte stream and fills the
// image buffer.
//
//   Frame:  0xA5  |  ndigits(0x01 or 0x02)  |  ndigits * 784 pixel bytes
//   Pixels: any non-zero byte is stored as 1 (ink), zero as 0 (background),
//           row-major 28x28, MSB digit (tens) first when ndigits==2.
//
// Emits frame_done (1-cycle pulse) with ndigits once the last pixel is stored.
// ---------------------------------------------------------------------------
module frame_rx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,        // uart_rx rx_data_valid
    // image buffer write port
    output reg         img_we,
    output reg  [10:0] img_waddr,
    output reg  [7:0]  img_wdata,
    // result
    output reg  [1:0]  ndigits,
    output reg         frame_done
);
    localparam SYNC = 8'hA5;
    localparam S_SYNC=2'd0, S_NDIG=2'd1, S_IMG=2'd2;

    reg [1:0]  state;
    reg        rx_d;
    wire       stb = rx_valid & ~rx_d;   // one strobe per received byte
    reg [10:0] cnt;
    reg [10:0] total;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_SYNC; rx_d<=0; cnt<=0; total<=0;
            ndigits<=0; frame_done<=0; img_we<=0; img_waddr<=0; img_wdata<=0;
        end else begin
            rx_d       <= rx_valid;
            frame_done <= 1'b0;
            img_we     <= 1'b0;
            if (stb) begin
                case (state)
                    S_SYNC:
                        if (rx_data==SYNC) state<=S_NDIG;
                    S_NDIG: begin
                        if (rx_data[1:0]==2'd2) begin ndigits<=2'd2; total<=11'd1568; end
                        else                    begin ndigits<=2'd1; total<=11'd784;  end
                        cnt   <= 11'd0;
                        state <= S_IMG;
                    end
                    S_IMG: begin
                        img_we    <= 1'b1;
                        img_waddr <= cnt;
                        img_wdata <= (rx_data!=8'd0) ? 8'd1 : 8'd0;
                        if (cnt == total-1) begin
                            frame_done <= 1'b1;
                            state      <= S_SYNC;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                endcase
            end
        end
    end
endmodule
