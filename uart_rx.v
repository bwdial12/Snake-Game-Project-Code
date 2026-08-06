
// UART receiver -- 8N1, 5-state FSM + 16-deep ring-buffer FIFO
// Receives w/a/s/d from a PC terminal to control snake direction
module uart_rx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 9600
)(
    input        clk,
    input        rst,
    input        i_rx_serial,
    input        i_rd_en,
    output [7:0] o_rx_byte,
    output reg   o_rx_dv,
    output       o_empty,
    output       o_full
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;
    localparam HALF_BIT     = CLKS_PER_BIT / 2;

    localparam [2:0]
        IDLE      = 3'd0,
        START_BIT = 3'd1,
        DATA_BITS = 3'd2,
        STOP_BIT  = 3'd3,
        CLEANUP   = 3'd4;

    // two-FF synchronizer for metastability
    reg rx_d0, rx_d1;
    always @(posedge clk) begin
        rx_d0 <= i_rx_serial;
        rx_d1 <= rx_d0;
    end

    reg [2:0]  state;
    reg [13:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  rx_byte;

    always @(posedge clk) begin
        if(rst) begin
            state   <= IDLE;
            clk_cnt <= 0;
            bit_idx <= 0;
            rx_byte <= 0;
            o_rx_dv <= 0;
        end else begin
            o_rx_dv <= 0;
            case(state)
                IDLE: begin
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if(rx_d1 == 1'b0)
                        state <= START_BIT;
                end

                START_BIT: begin
                    if(clk_cnt == HALF_BIT - 1) begin
                        clk_cnt <= 0;
                        if(rx_d1 == 1'b0) state <= DATA_BITS;
                        else              state <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

                DATA_BITS: begin
                    if(clk_cnt < CLKS_PER_BIT - 1)
                        clk_cnt <= clk_cnt + 1;
                    else begin
                        clk_cnt          <= 0;
                        rx_byte[bit_idx] <= rx_d1;
                        if(bit_idx < 7)
                            bit_idx <= bit_idx + 1;
                        else begin
                            bit_idx <= 0;
                            state   <= STOP_BIT;
                        end
                    end
                end

                STOP_BIT: begin
                    if(clk_cnt < CLKS_PER_BIT - 1)
                        clk_cnt <= clk_cnt + 1;
                    else begin
                        o_rx_dv <= 1'b1;
                        clk_cnt <= 0;
                        state   <= CLEANUP;
                    end
                end

                CLEANUP: state <= IDLE;

                default: state <= IDLE;
            endcase
        end
    end

    // 16-deep ring-buffer FIFO (matches professor's module_fifo_regs_no_flags style)
    localparam FDEPTH = 16;

    reg [7:0] fifo_mem [0:FDEPTH-1];
    reg [3:0] wr_idx, rd_idx;
    reg [4:0] count;

    assign o_rx_byte = fifo_mem[rd_idx];
    assign o_empty   = (count == 0);
    assign o_full    = (count == FDEPTH);

    always @(posedge clk) begin
        if(rst) begin
            wr_idx <= 0;
            rd_idx <= 0;
            count  <= 0;
        end else begin
            if(o_rx_dv && !o_full) begin
                fifo_mem[wr_idx] <= rx_byte;
                wr_idx           <= wr_idx + 1;
            end
            if(i_rd_en && !o_empty)
                rd_idx <= rd_idx + 1;

            case({o_rx_dv && !o_full, i_rd_en && !o_empty})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: ;
            endcase
        end
    end
endmodule
