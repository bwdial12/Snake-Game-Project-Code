`include "defines.vh"

// top-level game logic: FSM, direction control, food, score, UART events
module snake_game #(parameter SIM = 0) (
    input        clk,
    input        rst,

    input        sw1_edge,
    input        sw2, sw3, sw4,
    input        sw5,
    input [4:0]  sw_color,
    input [4:0]  sw_speed,

    input        btn_up, btn_dn, btn_lt, btn_rt,

    output reg [1:0]  game_state,
    output reg [15:0] score,
    output reg [15:0] hi_score,
    output     [8:0]  snake_len,

    output reg        uart_send,
    output reg [7:0]  uart_data,

    output [`MAX_LEN*9-1:0] body_flat,
    output reg [8:0]  food0_pos, food1_pos, food2_pos,
    output reg [2:0]  food_valid
);
    localparam [1:0] IDLE=0, PLAYING=1, PAUSED=2, GAME_OVER=3;

    wire [1:0] target_food = sw4 ? 2'd3 : sw3 ? 2'd2 : sw2 ? 2'd1 : 2'd0;

    wire [23:0] tick_lim;
    assign tick_lim = SIM         ? 24'd100        :
                      sw_speed[4] ? 24'd4_000_000  :
                      sw_speed[3] ? 24'd5_000_000  :
                      sw_speed[2] ? 24'd6_250_000  :
                      sw_speed[1] ? 24'd8_000_000  :
                      sw_speed[0] ? 24'd10_000_000 :
                                    24'd12_500_000;

    reg [23:0] tick_cnt;
    reg        game_tick;

    always @(posedge clk) begin
        if(rst || game_state != PLAYING) begin
            tick_cnt  <= 0;
            game_tick <= 0;
        end else if(tick_cnt >= tick_lim - 1) begin
            tick_cnt  <= 0;
            game_tick <= 1;
        end else begin
            tick_cnt  <= tick_cnt + 1;
            game_tick <= 0;
        end
    end

    reg [1:0] cur_dir, next_dir;

    always @(posedge clk) begin
        if(rst) begin
            cur_dir  <= `DIR_RIGHT;
            next_dir <= `DIR_RIGHT;
        end else if(game_state == PLAYING) begin
            if(btn_up  && cur_dir != `DIR_DOWN)  next_dir <= `DIR_UP;
            if(btn_dn  && cur_dir != `DIR_UP)    next_dir <= `DIR_DOWN;
            if(btn_lt  && cur_dir != `DIR_RIGHT) next_dir <= `DIR_LEFT;
            if(btn_rt  && cur_dir != `DIR_LEFT)  next_dir <= `DIR_RIGHT;
            if(game_tick) cur_dir <= next_dir;
        end
    end

    wire [15:0] lfsr_val;
    wire        lfsr_en = (game_state == PLAYING);
    lfsr16 u_lfsr (.clk(clk), .rst(rst), .en(lfsr_en), .val(lfsr_val));

    wire [4:0] sp_x = (lfsr_val[4:0] >= 20) ? lfsr_val[4:0] - 5'd20 : lfsr_val[4:0];
    wire [3:0] sp_y = (lfsr_val[9:6] >= 15) ? lfsr_val[9:6] - 4'd15 : lfsr_val[9:6];
    wire [8:0] spawn_pos = {sp_x, sp_y};

    reg        fifo_game_rst;
    reg        fifo_push, fifo_grow;
    reg [8:0]  fifo_din;
    wire [8:0] fifo_head;

    snake_fifo u_fifo (
        .clk(clk), .rst(rst),
        .game_rst(fifo_game_rst),
        .push(fifo_push), .grow(fifo_grow),
        .din(fifo_din),
        .head_pos(fifo_head), .tail_pos(),
        .len(snake_len),
        .body_flat(body_flat)
    );

    wire [4:0] hx = fifo_head[8:4];
    wire [3:0] hy = fifo_head[3:0];

    reg [4:0] new_hx;
    reg [3:0] new_hy;
    reg       wall_hit;

    always @(*) begin
        new_hx   = hx;
        new_hy   = hy;
        wall_hit = 0;
        case(cur_dir)
            `DIR_UP: begin
                if(hy == 0) begin wall_hit = sw5; new_hy = sw5 ? 4'd0 : 4'd14; end
                else new_hy = hy - 1;
            end
            `DIR_DOWN: begin
                if(hy == 14) begin wall_hit = sw5; new_hy = sw5 ? 4'd14 : 4'd0; end
                else new_hy = hy + 1;
            end
            `DIR_LEFT: begin
                if(hx == 0) begin wall_hit = sw5; new_hx = sw5 ? 5'd0 : 5'd19; end
                else new_hx = hx - 1;
            end
            `DIR_RIGHT: begin
                if(hx == 19) begin wall_hit = sw5; new_hx = sw5 ? 5'd19 : 5'd0; end
                else new_hx = hx + 1;
            end
        endcase
    end

    reg  self_hit;
    integer sc;
    always @(*) begin
        self_hit = 0;
        for(sc = 0; sc < `MAX_LEN - 1; sc = sc + 1) begin
            if(sc < snake_len - 1 &&
               body_flat[sc*9 +: 9] == {new_hx, new_hy})
                self_hit = 1;
        end
    end

    wire f0_hit = food_valid[0] && ({new_hx, new_hy} == food0_pos);
    wire f1_hit = food_valid[1] && ({new_hx, new_hy} == food1_pos);
    wire f2_hit = food_valid[2] && ({new_hx, new_hy} == food2_pos);
    wire ate    = f0_hit | f1_hit | f2_hit;

    function pos_free;
        input [8:0] p;
        integer j;
        begin
            pos_free = 1;
            for(j = 0; j < `MAX_LEN; j = j + 1)
                if(j < snake_len && body_flat[j*9 +: 9] == p)
                    pos_free = 0;
            if(food_valid[0] && food0_pos == p) pos_free = 0;
            if(food_valid[1] && food1_pos == p) pos_free = 0;
            if(food_valid[2] && food2_pos == p) pos_free = 0;
        end
    endfunction

    reg [1:0] init_cnt;
    reg       initializing;

    // FSM -- sole driver of: game_state, score, hi_score, uart_send, uart_data
    always @(posedge clk) begin
        if(rst) begin
            game_state <= IDLE;
            score      <= 0;
            hi_score   <= 0;
            uart_send  <= 0;
            uart_data  <= 0;
        end else begin
            uart_send <= 0;
            case(game_state)
                IDLE: begin
                    if(sw1_edge) begin
                        game_state <= PLAYING;
                        score      <= 0;    // reset score here, not in the FIFO block
                    end
                end
                PLAYING: begin
                    if(sw1_edge) game_state <= PAUSED;
                    if(game_tick && !initializing) begin
                        if(wall_hit || self_hit) begin
                            game_state <= GAME_OVER;
                            if(score > hi_score) hi_score <= score;
                            uart_send  <= 1;
                            uart_data  <= 8'hFF;
                        end else if(ate) begin
                            score     <= score + 1;
                            uart_send <= 1;
                            uart_data <= score[7:0] + 8'd1;
                        end
                    end
                end
                PAUSED:    if(sw1_edge) game_state <= PLAYING;
                GAME_OVER: if(sw1_edge) game_state <= IDLE;
            endcase
        end
    end

    // FIFO control and food management
    // sole driver of: fifo_*, initializing, init_cnt, food_*
    // score is NOT assigned here -- FSM block owns it exclusively
    always @(posedge clk) begin
        if(rst) begin
            fifo_push     <= 0; fifo_grow     <= 0;
            fifo_din      <= 0; fifo_game_rst <= 0;
            initializing  <= 0; init_cnt      <= 0;
            food_valid    <= 0;
            food0_pos <= 0; food1_pos <= 0; food2_pos <= 0;
        end else begin
            fifo_push     <= 0;
            fifo_grow     <= 0;
            fifo_game_rst <= 0;

            if(game_state == IDLE && sw1_edge) begin
                fifo_game_rst <= 1;
                initializing  <= 1;
                init_cnt      <= 0;
                food_valid    <= 0;
                // score reset is handled exclusively in the FSM block
            end

            // push 3 initial segments: (8,7),(9,7),(10,7) -- head at (10,7)
            if(initializing) begin
                fifo_push <= 1;
                fifo_grow <= 1;
                case(init_cnt)
                    2'd0: begin fifo_din <= {5'd8,  4'd7}; init_cnt <= 1; end
                    2'd1: begin fifo_din <= {5'd9,  4'd7}; init_cnt <= 2; end
                    2'd2: begin fifo_din <= {5'd10, 4'd7}; initializing <= 0; end
                endcase
            end

            if(game_state == PLAYING && !initializing && game_tick) begin
                if(!wall_hit && !self_hit) begin
                    fifo_din  <= {new_hx, new_hy};
                    fifo_push <= 1;
                    fifo_grow <= ate;
                end

                if(f0_hit) food_valid[0] <= 0;
                if(f1_hit) food_valid[1] <= 0;
                if(f2_hit) food_valid[2] <= 0;

                if(target_food >= 1 && !food_valid[0] && pos_free(spawn_pos)) begin
                    food0_pos <= spawn_pos; food_valid[0] <= 1;
                end else if(target_food >= 2 && !food_valid[1] && pos_free(spawn_pos)) begin
                    food1_pos <= spawn_pos; food_valid[1] <= 1;
                end else if(target_food >= 3 && !food_valid[2] && pos_free(spawn_pos)) begin
                    food2_pos <= spawn_pos; food_valid[2] <= 1;
                end
            end
        end
    end
endmodule
