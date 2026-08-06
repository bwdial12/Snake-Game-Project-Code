`include "defines.vh"

// shift-register FIFO for snake body
// index 0 = head (newest), index len-1 = tail (oldest)
// push=1, grow=0: normal move  (push new head, drop tail, len unchanged)
// push=1, grow=1: eating food  (push new head, keep tail, len++)
module snake_fifo (
    input             clk,
    input             rst,
    input             game_rst,
    input             push,
    input             grow,
    input      [8:0]  din,
    output     [8:0]  head_pos,
    output     [8:0]  tail_pos,
    output reg [8:0]  len,
    output reg [`MAX_LEN*9-1:0] body_flat
);
    reg [8:0] mem [0:`MAX_LEN-1];
    integer i;

    assign head_pos = mem[0];
    assign tail_pos = (len > 0) ? mem[len - 1] : 9'h1FF;

    always @(posedge clk) begin
        if(rst || game_rst) begin
            len <= 0;
        end else if(push) begin
            for(i = `MAX_LEN-1; i > 0; i = i - 1)
                mem[i] <= mem[i-1];
            mem[0] <= din;
            if(grow) len <= len + 1;
        end
    end

    // pack all entries into flat wire for renderer and collision checks
    always @(*) begin
        for(i = 0; i < `MAX_LEN; i = i + 1)
            body_flat[i*9 +: 9] = mem[i];
    end
endmodule
