
`include "defines.vh"
`timescale 1ns/1ps

module tb_top;

    reg        clk, rst;
    reg        btnc, btnu, btnd, btnl, btnr;
    reg [15:0] sw;
    reg        uart_rxd_tb;

    wire [15:0] led;
    wire [7:0]  an;
    wire [6:0]  seg;
    wire        dp;
    wire        vga_hs, vga_vs;
    wire [3:0]  vga_r, vga_g, vga_b;
    wire        uart_txd;

    top u_top (
        .clk(clk), .btnc(btnc),
        .btnu(btnu), .btnd(btnd),
        .btnl(btnl), .btnr(btnr),
        .sw(sw),
        .led(led), .an(an), .seg(seg), .dp(dp),
        .vga_hs(vga_hs), .vga_vs(vga_vs),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .uart_txd(uart_txd),
        .uart_rxd(uart_rxd_tb)
    );

    // override SIM parameter for fast game ticks (100 cycles each)
    defparam u_top.u_game.SIM = 1;

    initial clk = 0;
    always #5 clk = ~clk;   // 100MHz

    localparam UART_TICKS = 100_000_000 / 9600;

    // send one byte over uart_rxd_tb (8N1, LSB first)
    task uart_send_byte;
        input [7:0] byte_val;
        integer b;
        begin
            uart_rxd_tb = 0;
            repeat(UART_TICKS) @(posedge clk);
            for(b = 0; b < 8; b = b + 1) begin
                uart_rxd_tb = byte_val[b];
                repeat(UART_TICKS) @(posedge clk);
            end
            uart_rxd_tb = 1;
            repeat(UART_TICKS) @(posedge clk);
        end
    endtask

    // hold a button for 50 cycles then release
    task press_btn;
        input [4:0] which;
        begin
            {btnu, btnd, btnl, btnr, btnc} = which;
            repeat(50) @(posedge clk);
            {btnu, btnd, btnl, btnr, btnc} = 5'd0;
            repeat(10) @(posedge clk);
        end
    endtask

    task toggle_sw;
        input [3:0] idx;
        begin
            sw[idx] = ~sw[idx];
            @(posedge clk);
        end
    endtask

    // wait for n game ticks (SIM tick = 100 cycles, plus margin)
    task wait_ticks;
        input [7:0] n;
        integer t;
        begin
            for(t = 0; t < n; t = t + 1)
                repeat(110) @(posedge clk);
        end
    endtask

    task check_state;
        input [1:0] expected;
        begin
            if(u_top.u_game.game_state !== expected)
                $display("FAIL: state=%0d expected=%0d at t=%0t",
                    u_top.u_game.game_state, expected, $time);
            else
                $display("PASS: state=%0d at t=%0t", expected, $time);
        end
    endtask

    task check_score;
        input [15:0] expected;
        begin
            if(u_top.u_game.score !== expected)
                $display("FAIL: score=%0d expected=%0d", u_top.u_game.score, expected);
            else
                $display("PASS: score=%0d", expected);
        end
    endtask

    integer j;

    initial begin
        clk=0; btnc=0; btnu=0; btnd=0; btnl=0; btnr=0;
        sw=16'd0; uart_rxd_tb=1;

        // reset
        btnc=1; repeat(10) @(posedge clk); btnc=0;
        repeat(10) @(posedge clk);
        check_state(0);  // IDLE

        // configure: 1 apple, speed level 1
        sw[2]  = 1;
        sw[11] = 1;
        @(posedge clk);

        // start game via SW1 toggle
        toggle_sw(1);
        repeat(5) @(posedge clk);
        check_state(1);  // PLAYING

        // run several ticks moving right (default direction)
        wait_ticks(4);
        check_state(1);
        check_score(0);

        // test all 4 directions via buttons
        for(j = 0; j < 4; j = j + 1) begin
            case(j[1:0])
                2'd0: press_btn(5'b01000);  // down
                2'd1: press_btn(5'b00100);  // left
                2'd2: press_btn(5'b10000);  // up
                2'd3: press_btn(5'b00010);  // right
            endcase
            wait_ticks(2);
        end
        check_state(1);

        // pause via SW1
        toggle_sw(1);
        repeat(5) @(posedge clk);
        check_state(2);  // PAUSED

        // resume via UART 'p' character
        uart_send_byte(8'h70);
        repeat(10) @(posedge clk);
        check_state(1);  // PLAYING

        // steer via UART a/s/d
        uart_send_byte(8'h61);  // 'a' = left
        wait_ticks(2);
        uart_send_byte(8'h73);  // 's' = down
        wait_ticks(2);
        uart_send_byte(8'h64);  // 'd' = right
        wait_ticks(2);
        check_state(1);

        // enable wall-deadly, crash snake into wall
        sw[5] = 1;
        repeat(22) begin
            press_btn(5'b10000);  // keep pressing up
            wait_ticks(1);
        end
        wait_ticks(2);
        check_state(3);  // GAME_OVER

        // restart via UART 'p'
        uart_send_byte(8'h70);
        repeat(5) @(posedge clk);
        check_state(0);  // IDLE

        toggle_sw(1);
        repeat(5) @(posedge clk);
        check_state(1);  // PLAYING
        check_score(0);  // score reset on new game

        $display("Simulation complete.");
        $finish;
    end

endmodule
