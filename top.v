`include "defines.vh"

module top (
    input        clk,

    input        btnc,
    input        btnu, btnd, btnl, btnr,

    input [15:0] sw,

    output [15:0] led,

    output [7:0] an,
    output [6:0] seg,
    output       dp,

    output       vga_hs,
    output       vga_vs,
    output [3:0] vga_r,
    output [3:0] vga_g,
    output [3:0] vga_b,

    output       uart_txd,
    input        uart_rxd
);
    wire rst = btnc;

    // debounce all 5 buttons via for-generate
    wire [4:0] btn_raw   = {btnu, btnd, btnl, btnr, btnc};
    wire [4:0] btn_clean;

    genvar i;
    generate
        for(i = 0; i < 5; i = i + 1) begin : gen_db
            debounce #(.N(20)) u_db (
                .clk(clk), .rst(rst),
                .in(btn_raw[i]), .out(btn_clean[i])
            );
        end
    endgenerate

    // rising-edge detect on each clean button
    wire [4:0] btn_edge;
    generate
        for(i = 0; i < 5; i = i + 1) begin : gen_ed
            edge_detect u_ed (
                .clk(clk), .sig(btn_clean[i]),
                .pos(btn_edge[i]), .neg()
            );
        end
    endgenerate

    // edge on SW1 for start/pause
    wire sw1_edge;
    edge_detect u_sw1 (.clk(clk), .sig(sw[1]), .pos(sw1_edge), .neg());

    // UART RX -- receives w/a/s/d from PC terminal
    wire [7:0] rx_char;
    wire       rx_dv;

    uart_rx #(.CLK_FREQ(100_000_000), .BAUD(9600)) u_uart_rx (
        .clk(clk), .rst(rst),
        .i_rx_serial(uart_rxd),
        .i_rd_en(1'b0),
        .o_rx_byte(rx_char),
        .o_rx_dv(rx_dv),
        .o_empty(), .o_full()
    );

    // decode UART chars to direction pulses
    // w/W=up, s/S=down, a/A=left, d/D=right, p/P=pause
    wire uart_up   = rx_dv && (rx_char == 8'h77 || rx_char == 8'h57);
    wire uart_dn   = rx_dv && (rx_char == 8'h73 || rx_char == 8'h53);
    wire uart_lt   = rx_dv && (rx_char == 8'h61 || rx_char == 8'h41);
    wire uart_rt   = rx_dv && (rx_char == 8'h64 || rx_char == 8'h44);
    wire uart_paus = rx_dv && (rx_char == 8'h70 || rx_char == 8'h50);

    // OR UART commands with physical button/switch edges
    wire final_up  = btn_edge[4] | uart_up;
    wire final_dn  = btn_edge[3] | uart_dn;
    wire final_lt  = btn_edge[2] | uart_lt;
    wire final_rt  = btn_edge[1] | uart_rt;
    wire final_sw1 = sw1_edge    | uart_paus;

    // game core
    wire [1:0]  game_state;
    wire [15:0] score, hi_score;
    wire [8:0]  snake_len;
    wire        uart_send;
    wire [7:0]  uart_data;
    wire [`MAX_LEN*9-1:0] body_flat;
    wire [8:0]  food0_pos, food1_pos, food2_pos;
    wire [2:0]  food_valid;

    snake_game #(.SIM(0)) u_game (
        .clk(clk), .rst(rst),
        .sw1_edge(final_sw1),
        .sw2(sw[2]), .sw3(sw[3]), .sw4(sw[4]),
        .sw5(sw[5]),
        .sw_color(sw[10:6]),
        .sw_speed(sw[15:11]),
        .btn_up(final_up), .btn_dn(final_dn),
        .btn_lt(final_lt), .btn_rt(final_rt),
        .game_state(game_state),
        .score(score), .hi_score(hi_score),
        .snake_len(snake_len),
        .uart_send(uart_send), .uart_data(uart_data),
        .body_flat(body_flat),
        .food0_pos(food0_pos), .food1_pos(food1_pos), .food2_pos(food2_pos),
        .food_valid(food_valid)
    );

    // VGA
    wire        vga_active;
    wire [9:0]  vga_px, vga_py;
    wire [11:0] rgb;

    vga_sync u_vga (
        .clk(clk), .rst(rst),
        .hsync(vga_hs), .vsync(vga_vs),
        .active(vga_active),
        .px(vga_px), .py(vga_py)
    );

    renderer u_rend (
        .clk(clk),
        .active(vga_active),
        .px(vga_px), .py(vga_py),
        .game_state(game_state),
        .sw_color(sw[10:6]),
        .sw0(sw[0]),
        .score(score),
        .body_flat(body_flat),
        .snake_len(snake_len),
        .food0_pos(food0_pos), .food1_pos(food1_pos), .food2_pos(food2_pos),
        .food_valid(food_valid),
        .rgb(rgb)
    );

    assign {vga_r, vga_g, vga_b} = rgb;

    // UART TX
    uart_tx #(.CLK_FREQ(100_000_000), .BAUD(9600)) u_uart_tx (
        .clk(clk), .rst(rst),
        .send(uart_send), .data(uart_data),
        .tx(uart_txd),
        .tx_active(), .tx_done()
    );

    // 7-seg: left 4 digits = score, right 4 = hi_score (SW4=0) or snake_len (SW4=1)
    wire [31:0] seg_val = sw[4] ?
        {score, 7'd0, snake_len} :
        {score, hi_score};

    seg7_driver u_seg (
        .clk(clk), .rst(rst),
        .val(seg_val),
        .an(an), .seg(seg)
    );
    assign dp = 1'b1;

    // LEDs: [15:12] game state one-hot, [11:8] speed level, [7:0] length bar
    wire [3:0] state_leds = 4'b0001 << game_state;
    wire [3:0] speed_leds = sw[15:12];

    wire [7:0] len_bar;
    assign len_bar[0] = (snake_len >= 9'd1);
    assign len_bar[1] = (snake_len >= 9'd19);
    assign len_bar[2] = (snake_len >= 9'd38);
    assign len_bar[3] = (snake_len >= 9'd56);
    assign len_bar[4] = (snake_len >= 9'd75);
    assign len_bar[5] = (snake_len >= 9'd94);
    assign len_bar[6] = (snake_len >= 9'd113);
    assign len_bar[7] = (snake_len >= 9'd131);

    assign led = {state_leds, speed_leds, len_bar};
endmodule
