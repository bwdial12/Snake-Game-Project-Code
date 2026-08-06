
// UART transmitter -- 8N1, explicit 5-state FSM
module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 9600
)(
    input        clk,
    input        rst,
    input        send,
    input  [7:0] data,
    output reg   tx,
    output reg   tx_active,
    output reg   tx_done
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;

    localparam [2:0]
        IDLE      = 3'd0,
        START_BIT = 3'd1,
        DATA_BITS = 3'd2,
        STOP_BIT  = 3'd3,
        CLEANUP   = 3'd4;

    reg [2:0]  state;
    reg [13:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  tx_data;

    always @(posedge clk) begin
        if(rst) begin
            state     <= IDLE;
            tx        <= 1'b1;
            tx_active <= 0;
            tx_done   <= 0;
            clk_cnt   <= 0;
            bit_idx   <= 0;
        end else begin
            case(state)
                IDLE: begin
                    tx        <= 1'b1;
                    tx_active <= 0;
                    tx_done   <= 0;
                    clk_cnt   <= 0;
                    bit_idx   <= 0;
                    if(send) begin
                        tx_data <= data;
                        state   <= START_BIT;
                    end
                end

                START_BIT: begin
                    tx_active <= 1;
                    tx        <= 1'b0;
                    if(clk_cnt < CLKS_PER_BIT - 1)
                        clk_cnt <= clk_cnt + 1;
                    else begin
                        clk_cnt <= 0;
                        state   <= DATA_BITS;
                    end
                end

                DATA_BITS: begin
                    tx <= tx_data[bit_idx];
                    if(clk_cnt < CLKS_PER_BIT - 1)
                        clk_cnt <= clk_cnt + 1;
                    else begin
                        clk_cnt <= 0;
                        if(bit_idx < 7)
                            bit_idx <= bit_idx + 1;
                        else begin
                            bit_idx <= 0;
                            state   <= STOP_BIT;
                        end
                    end
                end

                STOP_BIT: begin
                    tx <= 1'b1;
                    if(clk_cnt < CLKS_PER_BIT - 1)
                        clk_cnt <= clk_cnt + 1;
                    else begin
                        clk_cnt <= 0;
                        tx_done <= 1;
                        state   <= CLEANUP;
                    end
                end

                CLEANUP: begin
                    tx_active <= 0;
                    tx_done   <= 1;
                    state     <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
