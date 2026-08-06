
`include "defines.vh"

module renderer (
    input        clk,
    input        active,
    input  [9:0] px, py,
    input  [1:0] game_state,
    input  [4:0] sw_color,
    input        sw0,
    input [15:0] score,
    input [`MAX_LEN*9-1:0] body_flat,
    input [8:0]  snake_len,
    input [8:0]  food0_pos, food1_pos, food2_pos,
    input [2:0]  food_valid,
    output reg [11:0] rgb
);
    localparam [1:0] IDLE=0, PLAYING=1, PAUSED=2, GAME_OVER=3;

    // all wires declared first, assigned below
    wire [4:0] cx;
    wire [3:0] cy;
    wire [8:0] pix_cell;
    wire [9:0] bar_w;
    wire       in_score_bar;
    wire       blink;
    wire [`MAX_LEN-1:0] hit_mask;
    wire                in_snake;

    reg [25:0] blink_cnt;
    reg [8:0]  seg_idx;
    integer    m;

    // continuous assignments separate from declarations
    assign cx           = px[9:5];
    assign cy           = py[8:5];
    assign pix_cell     = {cx, cy};
    assign bar_w        = (score < 10'd160) ? {score[7:0], 2'b00} : 10'd640;
    assign in_score_bar = sw0 && (py < 10'd8) && (px < bar_w);
    assign blink        = blink_cnt[25];
    assign in_snake     = |hit_mask;

    function [11:0] snake_rgb;
        input [8:0] idx;
        input [4:0] csw;
        reg [2:0] ci;
        begin
            if(csw[4]) begin
                case(idx % 5)
                    3'd0:    ci = `COL_WHITE;
                    3'd1:    ci = `COL_BLUE;
                    3'd2:    ci = `COL_GREEN;
                    3'd3:    ci = `COL_RED;
                    default: ci = `COL_YELLOW;
                endcase
            end else if(csw[3:0] == 4'd0) begin
                ci = `COL_WHITE;
            end else begin
                case(idx[1:0])
                    2'd0: ci = csw[0] ? `COL_BLUE   :
                                csw[1] ? `COL_GREEN  :
                                csw[2] ? `COL_RED    : `COL_YELLOW;
                    2'd1: ci = csw[1] ? `COL_GREEN  :
                                csw[2] ? `COL_RED    :
                                csw[3] ? `COL_YELLOW :
                                csw[0] ? `COL_BLUE   : `COL_WHITE;
                    2'd2: ci = csw[2] ? `COL_RED    :
                                csw[3] ? `COL_YELLOW :
                                csw[0] ? `COL_BLUE   :
                                csw[1] ? `COL_GREEN  : `COL_WHITE;
                    2'd3: ci = csw[3] ? `COL_YELLOW :
                                csw[0] ? `COL_BLUE   :
                                csw[1] ? `COL_GREEN  :
                                csw[2] ? `COL_RED    : `COL_WHITE;
                    default: ci = `COL_WHITE;
                endcase
            end
            case(ci)
                `COL_WHITE:  snake_rgb = 12'hFFF;
                `COL_BLUE:   snake_rgb = 12'h00F;
                `COL_GREEN:  snake_rgb = 12'h0F0;
                `COL_RED:    snake_rgb = 12'hF00;
                `COL_YELLOW: snake_rgb = 12'hFF0;
                default:     snake_rgb = 12'hFFF;
            endcase
        end
    endfunction

    // 300 parallel comparators via for-generate
    genvar k;
    generate
        for(k = 0; k < `MAX_LEN; k = k + 1) begin : gen_hit
            assign hit_mask[k] = (k < snake_len) &&
                                 (body_flat[k*9 +: 9] == pix_cell);
        end
    endgenerate

    always @(posedge clk)
        blink_cnt <= blink_cnt + 1;

    // lowest matching segment index wins (head = index 0)
    always @(*) begin
        seg_idx = 9'd0;
        for(m = `MAX_LEN - 1; m >= 0; m = m - 1)
            if(hit_mask[m]) seg_idx = m[8:0];
    end

    // pixel color output -- PLAYING and PAUSED are separate cases
    always @(*) begin
        if(!active) begin
            rgb = 12'h000;
        end else begin
            case(game_state)
                IDLE: begin
                    rgb = blink ? ((px[5] ^ py[5]) ? 12'h003 : 12'h006)
                                : 12'h000;
                end
                GAME_OVER: begin
                    rgb = in_snake ? 12'hF00 :
                          blink    ? 12'h400 : 12'h200;
                end
                PLAYING: begin
                    if(in_score_bar) begin
                        rgb = 12'h0FF;
                    end else if(in_snake) begin
                        rgb = snake_rgb(seg_idx, sw_color);
                    end else if(food_valid[0] && (food0_pos == pix_cell)) begin
                        rgb = 12'hF80;
                    end else if(food_valid[1] && (food1_pos == pix_cell)) begin
                        rgb = 12'hF0F;
                    end else if(food_valid[2] && (food2_pos == pix_cell)) begin
                        rgb = 12'hFF0;
                    end else begin
                        rgb = 12'h000;
                    end
                end
                PAUSED: begin
                    if(in_score_bar) begin
                        rgb = 12'h0FF;
                    end else if(in_snake) begin
                        rgb = snake_rgb(seg_idx, sw_color);
                    end else if(food_valid[0] && (food0_pos == pix_cell)) begin
                        rgb = 12'hF80;
                    end else if(food_valid[1] && (food1_pos == pix_cell)) begin
                        rgb = 12'hF0F;
                    end else if(food_valid[2] && (food2_pos == pix_cell)) begin
                        rgb = 12'hFF0;
                    end else begin
                        rgb = 12'h111;
                    end
                end
                default: rgb = 12'h000;
            endcase
        end
    end

endmodule
